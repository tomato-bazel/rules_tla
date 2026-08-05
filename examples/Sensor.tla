------------------------------- MODULE Sensor -------------------------------
\* REGRESSION TEST for the TLA-Library bug: this module EXTENDS a module that
\* lives in another package and is supplied through `deps`. Under 0.1.0/0.1.1
\* it fails with "Cannot find source file for module Bounded", which reads as a
\* missing dep rather than as the rule discarding the dep it was given.
EXTENDS Bounded

VARIABLE v

Init == v = 0
Next == v' = IF v = Cap THEN 0 ELSE v + 1

Spec == Init /\ [][Next]_v /\ WF_v(Next)

TypeOK == InRange(v)

Cycles == []<>(v = 0)
=============================================================================
