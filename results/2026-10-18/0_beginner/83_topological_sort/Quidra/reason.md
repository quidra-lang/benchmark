# Task B selection: 83_topological_sort / Quidra

## Common answer requirements

Reverse only ready-course selection. Preserve recomputation, termination, and the ascending cycle output.

## Source evidence

The course list is sorted ascending. The scan takes the first untaken course of zero indegree. Scan those indices in descending order instead, retaining the stop when no eligible course is found, marking the selected course and decrementing outgoing targets before rescanning. Leave the ascending ordered array and the cycle filter in that order.

## Minimization

The cycle filter shares the ordered array, so the excerpt must show why reversing the common array would change the cycle output. Graph construction and datasets are unchanged. Selected complete lines of `main.qui`: 4, 5, 10, 11, 12, 13, 14, 15, 16, 17, 18, 20, 21, 23, 24, 25.
