# Task B selection: 10_fibonacci / Quidra

## Common answer requirements

Extend the recurrence to exactly 40 terms and retain exact accumulation and the two-line output.

## Source evidence

The two initial values and the simultaneous update generate the recurrence in order. The inclusive loop bound determines which terms are both printed and added to total. Its upper bound becomes 40, with the same integer types, recurrence, and output calls. The final line-output call begins with NL, separating the sum label from the values.

## Minimization

The space-printing condition is untouched. The term emission and the final sum emission establish which loop output and accumulated value the changed bound affects. Selected complete lines of `main.qui`: 1, 2, 3, 4, 7, 8, 9, 10.
