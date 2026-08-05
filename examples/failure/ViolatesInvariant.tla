-------------------------- MODULE ViolatesInvariant --------------------------
\* A counter mod 5 carrying the invariant of a counter mod 3.
EXTENDS Naturals

VARIABLE x

Init == x = 0
Next == x' = (x + 1) % 5

Spec == Init /\ [][Next]_x /\ WF_x(Next)

\* False: x reaches 3 and 4.
TypeOK == x \in 0..2
=============================================================================
