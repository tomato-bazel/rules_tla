----------------------------- MODULE NeverSettles -----------------------------
\* A ring counter with NO fairness, so a behavior may stutter forever and
\* `<>[](x = 2)` fails. Every state has a successor, so this fails on the
\* temporal property and nothing else — a deadlock here would mean the probe
\* was testing the wrong path.
EXTENDS Naturals

VARIABLE x

Init == x = 0

Next == \/ (x < 2 /\ x' = x + 1)
        \/ (x = 2 /\ x' = 0)

Spec == Init /\ [][Next]_x

\* False: the behavior that never takes a step never settles at 2.
Reaches == <>[](x = 2)
=============================================================================
