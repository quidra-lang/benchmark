# Task B selection: 83_topological_sort / Python

## Common answer requirements

Reverse only ready-course selection. Preserve recomputation, termination, and the ascending cycle output.

## Source evidence

The ready list starts sorted ascending and is sorted again after outgoing indegrees are updated. Pop the last rather than first entry. Keep the while-ready condition and the newly eligible appends. The independently sorted difference between courses and order remains ascending for the cycle.

## Minimization

The ready loop, its updates, and independent sorted result establish that pop selection is the only change. Graph construction and datasets are unchanged. Selected complete lines of `main.py`: 7, 9, 10, 11, 12, 13, 14, 15, 16, 17.
