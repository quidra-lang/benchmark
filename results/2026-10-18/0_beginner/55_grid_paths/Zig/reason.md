# Task B selection: 55_grid_paths / Zig

## Common answer requirements

Add one down-right move to both path counts, checking only the destination for obstacles and preserving the existing outputs.

## Source evidence

The row/column sweep accumulates counts from above and left, with destination filtering before the recurrence. Add the count at the preceding row and column when both predecessors exist, in the same passable destination path. Do not test the two orthogonal neighbors: their passability determines their own counts. The source seed still represents the empty path at the start, and both obstacle modes share the updated recurrence.

## Minimization

The grid contents and unaffected output do not change. The mode binding, destination filter and predecessor updates show where to add the new term.

Selected complete lines of `main.zig`: 8–21. The prior excerpt measured 266 tokens; this excerpt measures 254 with `metric/tokenizer.py`.
