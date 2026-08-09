"""tla_check — model-check a TLA+ spec with TLC as a `bazel test` target.

Implemented as a build action that runs TLC and writes a marker file, gated by a
`build_test`. Running TLC in an action (rather than a test binary) means we use
exec-config file paths directly — no runfiles/rlocation wiring — and the JDK comes
from Bazel's built-in java runtime toolchain.
"""

load("@bazel_skylib//rules:build_test.bzl", "build_test")
load(":providers.bzl", "TlaInfo")

def _tla_check_run_impl(ctx):
    java_runtime = ctx.toolchains["@bazel_tools//tools/jdk:runtime_toolchain_type"].java_runtime
    java = java_runtime.java_executable_exec_path

    jar = ctx.file._tla2tools
    module = ctx.file.module
    config = ctx.file.config

    dep_sources = depset(
        transitive = [dep[TlaInfo].transitive_sources for dep in ctx.attr.deps],
    ).to_list()

    # TLC's module search path (TLA-Library): the directory of the root module
    # plus every directory holding a transitive dependency module, so `EXTENDS`
    # resolves across packages. Standard modules (Naturals, Sequences, …) are
    # bundled in the jar.
    lib_dirs = {module.dirname: True}
    for f in dep_sources:
        lib_dirs[f.dirname] = True
    tla_library_path = ":".join(lib_dirs.keys())

    marker = ctx.actions.declare_file(ctx.label.name + ".tlc.ok")

    inputs = depset(
        [jar, module, config] + dep_sources,
        transitive = [java_runtime.files],
    )

    # TLC writes scratch/metadata; send it to a private metadir so it never
    # touches the read-only sandboxed input tree. Fail on non-zero exit (TLC
    # returns non-zero on violations) and also scan the log as a belt-and-braces
    # guard for the rare "exit 0 but violated" case.
    #
    # ⛔ `-Djava.io.tmpdir` IS LOAD-BEARING AND ITS ABSENCE IS A CONCURRENCY BUG, NOT A
    # TIDINESS ISSUE. TLC does not read the standard modules (Naturals, Sequences,
    # FiniteSets, …) from the jar in place — it EXTRACTS them to `java.io.tmpdir` under
    # FIXED names and registers them for deleteOnExit. Two `tla_check` targets building
    # concurrently therefore extract to the same paths and delete each other's copies,
    # and the loser fails with
    #
    #     Error: source file 'Sequences.tla' has apparently been deleted.
    #     Error: Parsing or semantic analysis failed.
    #
    # ⚠ WHICH LOOKS LIKE A BROKEN SPEC, NOT A RACE. Measured in tomato-bazel/infra with 11
    # tla_check targets: roughly one run in three had 2-3 spurious failures, each naming a
    # different module, and every one of them passed when re-run alone. A test suite that
    # fails a third of the time for a reason that points at the user's own file is worse
    # than no suite at all.
    #
    # `$MD` is already per-action (mktemp -d) and already cleaned up by the trap, so
    # pointing the JVM at it costs nothing and makes the extraction private.
    # ⭐ `expect_violation` INVERTS BOTH CHECKS, AND IT IS WHAT KEEPS A SPEC HONEST.
    # A model check that passes tells you the property held; it does not tell you the
    # property could ever have failed. A spec that idealises the thing it models — one
    # whose actions describe the program somebody meant to write — proves true things
    # about nothing, silently and forever, and reads exactly like a spec that works.
    #
    # The fix is a target per defect: mutate one constant so the implementation's real
    # (or historical) behaviour is reachable, and REQUIRE the violation. A green run on
    # an expect_violation target means the property has stopped constraining anything.
    #
    # ⚠ A parse or semantic error is NOT a violation. TLC exits non-zero for both, so an
    # inverted target would otherwise pass on a spec that no longer compiles — which is
    # the same failure one level up. `^Error:` from SANY is checked for separately and
    # fails either way.
    if ctx.attr.expect_violation:
        verdict = """
if grep -qiE '^Error: (Parsing|Semantic|Evaluation)|was not (parsed|found)|Unknown location' "$LOG"; then
    echo "rules_tla: the spec did not compile — an expect_violation target cannot be satisfied by a broken spec" >&2
    exit 1
fi
if grep -qiE 'is violated|Temporal properties were violated|Deadlock reached' "$LOG"; then
    echo "rules_tla: violation reported, as this target requires"
else
    echo "rules_tla: EXPECTED A VIOLATION AND TLC REPORTED NONE." >&2
    echo "  The property this target mutates no longer constrains anything." >&2
    exit 1
fi
"""
    else:
        verdict = """
if [ "$TLC_OK" -ne 0 ]; then
    echo "rules_tla: TLC exited non-zero" >&2
    exit 1
fi
if grep -qiE 'is violated|Temporal properties were violated|Deadlock reached|^Error:' "$LOG"; then
    echo "rules_tla: TLC reported a violation" >&2
    exit 1
fi
"""

    command = """
set -uo pipefail
MD="$(mktemp -d)"
trap 'rm -rf "$MD"' EXIT
LOG="$MD/tlc.log"
# Run without `set -e` semantics: an expect_violation target NEEDS the non-zero
# exit, so the status is captured rather than allowed to abort the script.
if "{java}" -XX:+UseParallelGC -Djava.io.tmpdir="$MD" -DTLA-Library="{libpath}" \
        -cp "{jar}" tlc2.TLC \
        -metadir "$MD" -config "{config}" "{module}" 2>&1 | tee "$LOG"; then
    TLC_OK=0
else
    TLC_OK=1
fi
{verdict}
touch "{marker}"
""".format(
        java = java,
        libpath = tla_library_path,
        jar = jar.path,
        config = config.path,
        module = module.path,
        marker = marker.path,
        verdict = verdict,
    )

    ctx.actions.run_shell(
        inputs = inputs,
        outputs = [marker],
        command = command,
        mnemonic = "TlcCheck",
        progress_message = "TLC checking %s" % module.short_path,
    )
    return [DefaultInfo(files = depset([marker]))]

_tla_check_run = rule(
    implementation = _tla_check_run_impl,
    attrs = {
        "module": attr.label(
            allow_single_file = [".tla"],
            mandatory = True,
            doc = "The root TLA+ module to check.",
        ),
        "config": attr.label(
            allow_single_file = [".cfg"],
            mandatory = True,
            doc = "The TLC configuration file.",
        ),
        "deps": attr.label_list(
            providers = [TlaInfo],
            doc = "tla_library targets the module EXTENDS.",
        ),
        "expect_violation": attr.bool(
            default = False,
            doc = "Require TLC to report a violation. The target FAILS if the check passes.",
        ),
        "_tla2tools": attr.label(
            default = "@tla2tools//file",
            allow_single_file = True,
        ),
    },
    toolchains = ["@bazel_tools//tools/jdk:runtime_toolchain_type"],
)

def tla_check(name, module, config, deps = [], expect_violation = False, **kwargs):
    """Model-check a TLA+ spec with TLC, as a `bazel test` target.

    Args:
      name: test target name.
      module: the root `.tla` module.
      config: the `.cfg` file (SPECIFICATION / INVARIANT / PROPERTY / CONSTANTS).
      deps: `tla_library` targets the module EXTENDS.
      expect_violation: invert the verdict — the target passes only if TLC reports
        a violation, and FAILS if the check comes back clean.

        ⭐ This is how a spec is kept honest. Passing tells you a property held; it
        does not tell you the property could ever have failed. Pair each real check
        with a target that mutates one constant so the defect is reachable, and
        require the violation. If that target ever goes green, the property has
        stopped constraining anything — which is exactly how a spec ends up proving
        true statements about a program nobody wrote.
      **kwargs: forwarded to the wrapping `build_test` (e.g. tags, size).
    """
    _tla_check_run(
        name = name + ".run",
        module = module,
        config = config,
        deps = deps,
        expect_violation = expect_violation,
        testonly = True,
        tags = ["manual"],
    )
    build_test(
        name = name,
        targets = [":" + name + ".run"],
        **kwargs
    )
