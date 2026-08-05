------------------------------ MODULE Bounded ------------------------------
\* A helper module in a DIFFERENT Bazel package from the spec that EXTENDS it.
\* This is the whole point of `tla_library` + `deps`, and until the TLA-Library
\* fix nothing in this repo exercised it — so it was broken from 0.1.0 and no
\* check said so.
EXTENDS Naturals

Cap == 3

InRange(v) == v \in 0..Cap
=============================================================================
