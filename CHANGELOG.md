# Changelog

## 0.1.2 — `expect_violation`, so a spec can be shown to have teeth

`tla_check` gains `expect_violation`. The target passes only when TLC reports a
violation, and **fails when the check comes back clean**.

A passing model check tells you a property held. It does not tell you the property
could ever have failed — and a spec that idealises the thing it models proves true
statements about a program nobody wrote, silently, forever, reading exactly like a
spec that works. tomato-bazel/crova spent months in that state: its mapped index
was empty on every deployment and cost 8.1× on the miss path, while both of its
proven properties held, because the spec modelled a `Put` that recorded into the
table and a boot that checked the table against the store. The implementation did
neither.

The pattern this enables is a target per defect: mutate one constant so the real
behaviour is reachable, and require the violation.

```starlark
tla_check(name = "safety", module = "Spec.tla", config = "Safety.cfg")

tla_check(
    name = "mutation_put_does_not_record",
    module = "Spec.tla",
    config = "MutationNoRecordOnPut.cfg",
    expect_violation = True,   # a GREEN run here means the property is decoration
)
```

⚠ A parse or semantic error is **not** a violation. TLC exits non-zero for both, so
an inverted target would otherwise go green on a spec that no longer compiles —
which is the same failure one level up. SANY's parse and semantic errors are
detected separately and fail the target either way.

`//examples:expect_violation_check` is the self-test: a spec that violates its
invariant by construction, so the inversion itself cannot silently stop working.

## 0.1.1 — private `java.io.tmpdir` per check

TLC extracts the standard modules (`Naturals`, `Sequences`, …) from the jar to
`java.io.tmpdir` under fixed names and registers them for `deleteOnExit`, so two
concurrent `tla_check` targets deleted each other's copies. Measured in
tomato-bazel/infra with 11 targets: roughly one run in three had 2–3 spurious
failures, each naming a different module, and every one passed when re-run alone.
⚠ The failure looks like a broken spec, not a race.

## 0.1.0

- Initial release. `tla_library` + `tla_check` running TLC from a pinned,
  hermetic `tla2tools.jar` (v1.7.4). Checks run as build actions gated by
  `build_test`, so `bazel test //...` model-checks specs with no runfiles wiring.
- Transitive `tla_library` source directories are placed on TLC's `TLA-Library`
  search path.
