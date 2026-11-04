# Task B selection: 48_josephus_problem / Quidra

## Common answer requirements

Trace the first three removals of the source case n=7, k=3, including wraparound and where counting resumes.

## Source evidence

The source case supplies n=7 and k=3 to the destructuring loop. The circle starts as 1 through 7 and index starts at zero. Repeatedly advance by k minus one modulo the current length, then remove at that index. The next surviving person slides into the removed index, so the next count starts there. The first three removed people are 3, 6, and 2.

## Minimization

The array declaration and destructuring bind the focused case to the algorithm, as the inline case list does in Python. Output formatting and final-survivor output are unnecessary. Selected complete lines of `main.qui`: 1, 3, 4, 5, 6, 9, 10, 11.
