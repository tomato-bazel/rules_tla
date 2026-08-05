# Changelog

## 0.2.0

- **FIX: `deps` never worked.** `tla_check` passed the spec to TLC as
  `pkg/Module.tla`, and `tlc2.TLC.main` builds its resolver from the directory
  component of that path — a code path that never reads the `TLA-Library`
  system property. So `-DTLA-Library` was silently discarded on every
  invocation Bazel can produce, and any module reached through `deps` failed to
  resolve with `Cannot find source file for module X`, which reads as a missing
  `deps` entry rather than as the rule ignoring the one it was given. The action
  now `cd`s to the module's directory and passes a bare module name.
  `examples:sensor_check` is the regression test — it EXTENDS a module from
  another package, and it is the first thing in this repo ever to exercise
  `deps`.
- **New: `expect`.** Names the TLC outcome that makes a target pass — `ok`
  (default), `invariant_violation`, `deadlock`, `temporal_violation`. A
  counterexample you meant to keep can now be a checked property instead of a
  comment.
- **New: `tlc_args`** — flags passed through to `tlc2.TLC`.
- **New: `timeout_seconds`** — kills TLC after n seconds. A check runs in a build
  action and Bazel does not time actions out, so an infinite state space
  previously hung the build rather than failing it.
- **Fail closed.** A run that reports no error but never reaches "Model checking
  completed" (mistyped `-config`, empty cfg, usage dump) is now a failure. It
  used to pass.
- **CI.** There was none. `bazel test //...` now runs on ubuntu **and** macos,
  plus a step that builds a genuinely-violated spec under the default
  expectation and demands a non-zero exit, and a no-cache concurrent re-run that
  would catch a regression of the `java.io.tmpdir` race.

## 0.1.1

- `tla_check` gives TLC a private `java.io.tmpdir`. TLC extracts the standard
  modules to fixed names there and marks them `deleteOnExit`, so concurrent
  checks deleted each other's copies and the loser failed with
  `source file 'Sequences.tla' has apparently been deleted` — which looks like a
  broken spec rather than a race.

## 0.1.0

- Initial release. `tla_library` + `tla_check` running TLC from a pinned,
  hermetic `tla2tools.jar` (v1.7.4). Checks run as build actions gated by
  `build_test`, so `bazel test //...` model-checks specs with no runfiles wiring.
- Transitive `tla_library` source directories are placed on TLC's `TLA-Library`
  search path.
