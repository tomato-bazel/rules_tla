# rules_tla

Hermetic Bazel rules for **TLA+** model checking. Specs become first-class
`bazel test` targets: `bazel test //...` runs TLC and fails on any invariant,
deadlock, or temporal-property violation — the same way `rules_lean` makes Lean
proofs Bazel targets.

The TLA+ tools jar (`tla2tools.jar` — SANY + **TLC** + PlusCal) is pinned by
version + sha256 and fetched via `http_file`, so checks are reproducible. TLC runs
on the JDK that Bazel's built-in java runtime toolchain resolves.

## Usage

`MODULE.bazel`:

```starlark
bazel_dep(name = "rules_tla", version = "0.1.0")
```

`BUILD.bazel`:

```starlark
load("@rules_tla//tla:defs.bzl", "tla_library", "tla_check")

# Optional: group modules that other specs EXTEND.
tla_library(
    name = "lib",
    srcs = ["Helpers.tla"],
)

tla_check(
    name = "merge_queue_check",
    module = "MergeQueue.tla",
    config = "MergeQueue.cfg",
    deps = [":lib"],
)
```

Then:

```
bazel test //path/to:merge_queue_check
```

A `tla_check` passes iff TLC exits cleanly and reports no violation. A safety
(`INVARIANT`), deadlock, or temporal (`PROPERTY`) violation fails the test.

### Proving a property has teeth

A passing check tells you the property held. It does not tell you the property
**could ever have failed** — and that gap is not theoretical. A spec that models
the program somebody meant to write proves true statements about nothing, reads
exactly like a spec that works, and never goes red.

So pair each check with one that mutates a constant until the defect is reachable,
and require the violation:

```starlark
tla_check(name = "safety", module = "Spec.tla", config = "Safety.cfg")

tla_check(
    name = "mutation_put_does_not_record",
    module = "Spec.tla",
    config = "MutationNoRecordOnPut.cfg",
    expect_violation = True,
)
```

`expect_violation = True` inverts the verdict: the target **fails when the check
comes back clean**. A green mutation target means the property it mutates has
stopped constraining anything.

⚠ A parse or semantic error is not a violation. TLC exits non-zero for both, so
SANY's errors are detected separately and fail the target in either mode —
otherwise an inverted target would go green on a spec that no longer compiles.

## Rules

- **`tla_library(name, srcs, deps)`** — a group of `.tla` modules plus transitive
  `tla_library` deps. Provides `TlaInfo` (transitive sources) and its files via
  `DefaultInfo`. Directories of all transitive sources are placed on TLC's module
  search path (`TLA-Library`), so specs may `EXTENDS` modules from deps.
- **`tla_check(name, module, config, deps, expect_violation)`** — model-check
  `module` (a `.tla`) against `config` (a `.cfg`) with TLC, as a `bazel test`.
  Implemented as a build action (running TLC) gated by a `build_test`, so it needs
  no runfiles wiring. `expect_violation = True` inverts the verdict — see above.

## Scope

- **Engine: TLC** (explicit-state). Bounded checking at finite `CONSTANTS` is the
  first-line tool.
- **Deferred:** Apalache (symbolic/SMT) and TLAPS (machine-checked proofs) as
  alternate engines; PlusCal translation (`pcal`) as a `pluscal_translate` rule;
  and a separate `rules_p` for the P language.

## Hermeticity

- **Hermetic:** the `tla2tools.jar` (version + sha256 pinned in
  `tla/extensions.bzl`).
- **Toolchain-resolved:** the JDK (Bazel's `@bazel_tools//tools/jdk` runtime
  toolchain). Pinning a specific hermetic JDK is a follow-up.
