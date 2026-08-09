---- MODULE Broken ----
\* A spec that VIOLATES its invariant, on purpose.
\*
\* ⭐ THIS IS THE SELF-TEST FOR `expect_violation`, and it exists because the
\* feature's whole value is being able to fail. A gate that inverts the verdict is
\* only useful if the inversion actually works, and the way to know is a spec whose
\* check is guaranteed to come back red.
\*
\* The counter climbs past the bound the invariant asserts. Nothing subtle: the point
\* is a violation TLC cannot miss, so a green result here means the mechanism is
\* broken rather than the spec being clever.
EXTENDS Naturals

VARIABLE n

Init == n = 0
Next == n' = n + 1
Spec == Init /\ [][Next]_n

\* False the moment n reaches 3, which Next guarantees it will.
StaysSmall == n < 3
====
