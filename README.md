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
bazel_dep(name = "rules_tla", version = "0.2.0")
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

A `tla_check` passes iff TLC reaches "Model checking completed" and reports no
violation. A safety (`INVARIANT`), deadlock, or temporal (`PROPERTY`) violation
fails the test, and TLC's counterexample trace is printed in full.

## Rules

- **`tla_library(name, srcs, deps)`** — a group of `.tla` modules plus transitive
  `tla_library` deps. Provides `TlaInfo` (transitive sources) and its files via
  `DefaultInfo`. Directories of all transitive sources are placed on TLC's module
  search path (`TLA-Library`), so specs may `EXTENDS` modules from deps.
- **`tla_check(name, module, config, deps, expect, tlc_args, timeout_seconds)`** —
  model-check `module` (a `.tla`) against `config` (a `.cfg`) with TLC, as a
  `bazel test`. Implemented as a build action (running TLC) gated by a
  `build_test`, so it needs no runfiles wiring.

### Asserting that a design *does* break

`expect` names the TLC outcome that makes the target **pass**: `ok` (the
default), `invariant_violation`, `deadlock`, or `temporal_violation`. Any other
outcome fails, including a violation of a different kind than the one named.

```starlark
tla_check(
    name = "positive_cycle_never_settles",
    module = "MCCycle.tla",
    config = "MCCycle.cfg",
    expect = "temporal_violation",
)
```

This exists because a counterexample is often the result you want to keep. A
comment saying "this configuration does not terminate" decays; a target that
goes red the day it starts terminating does not. It is also the only way a green
suite can demonstrate that it is capable of failing — see `examples/failure/`.

### Bounding the run

`tlc_args` passes flags straight through to `tlc2.TLC` (`-workers`,
`-difftrace`, `-coverage`, `-simulate`, …).

`timeout_seconds` kills TLC after n seconds. ⚠ **A check runs in a build
action, and Bazel does not time actions out.** `size` and `timeout` on the
wrapping `build_test` govern the trivial test, not the model check, so a spec
with an infinite state space hangs the build rather than failing it. If a spec
can diverge, either give it a finite abstraction or set `timeout_seconds`.

## Scope

- **Engine: TLC** (explicit-state). Bounded checking at finite `CONSTANTS` is the
  first-line tool. A TLC result is only ever a statement about the state space it
  enumerated; it does not license an unbounded claim.
- **Deferred:** Apalache (symbolic/SMT) and TLAPS (machine-checked proofs) as
  alternate engines; PlusCal translation (`pcal`) as a `pluscal_translate` rule;
  and a separate `rules_p` for the P language.

## Hermeticity

- **Hermetic:** the `tla2tools.jar` (version + sha256 pinned in
  `tla/extensions.bzl`), fetched from an immutable GitHub **release asset** —
  not from `/archive/refs/tags/`, whose bytes GitHub does not guarantee.
- **Toolchain-resolved:** the JDK (Bazel's `@bazel_tools//tools/jdk` runtime
  toolchain). Pinning a specific hermetic JDK is a follow-up.

## Two traps this ruleset has already hit

Both are in `tla/private/tla_check.bzl` in full, with the diagnostics they
produce, because both look like the user's fault and neither is.

1. **The spec argument must be a bare module name.** `tlc2.TLC.main` builds its
   file resolver from the *directory component* of the spec path, and that code
   path never reads the `TLA-Library` system property. Any path with a directory
   in it — which is every path under Bazel — therefore silently discards
   `-DTLA-Library`, and `deps` modules become invisible with the message
   `Cannot find source file for module X`, which reads as a missing `deps` entry.
   This is why `deps` did not work in 0.1.0 or 0.1.1: the only example in the
   repo had no deps, so nothing exercised it.

2. **TLC needs a private `java.io.tmpdir`.** It extracts the standard modules
   (`Naturals`, `Sequences`, …) to fixed names under `java.io.tmpdir` and marks
   them `deleteOnExit`, so concurrent checks delete each other's copies and the
   loser fails with `source file 'Sequences.tla' has apparently been deleted` —
   which looks like a broken spec, not a race.
