------------------------------ MODULE Deadlocks ------------------------------
\* Counts up to 3 and then has no enabled action.
EXTENDS Naturals

VARIABLE x

Init == x = 0
Next == x < 3 /\ x' = x + 1

Spec == Init /\ [][Next]_x

TypeOK == x \in 0..3
=============================================================================
