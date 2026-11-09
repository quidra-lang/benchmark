# Task B selection — C++

## Answer requirements shared across languages

1. Distinguish absent stored solution from a stored solution associated with another current position, and locate the ordered error guards before any execution.
2. Trace the successful PLAY path through stored notation, movement execution, current-position/history updates and conditional redo clearing.
3. Explain result text and stored-solution retention, and split only the two failure messages without executing moves, discarding the solution, or changing successful behavior.

## Selected source locations

- `main.cpp`: 81, 82, 124, 125, 232, 233, 713, 751, 752, 753, 754, 755, 756, 757, 758, 760, 761, 762, 763, 764, 765, 768, 769, 770, 771, 772, 773, 774, 775, 1098, 1099, 1100, 1101, 1102, 1103, 1104, 1105

## Evidence and language semantics

The optional solution distinguishes no value from a position mismatch. Both checks throw before takeSteps. simulate is const, and takeSteps writes current, history and redoList only; notation is copied before execution. For a valid stored solution at the current position, the selected loop executes its notation in order and the commit helper appends the executed move letters; redo clears only when at least one letter was executed. The played result reports pushes and notation length. No selected success path deletes the stored solution. On either new failure, the early return/exception precedes every movement and history update. The excerpt alone identifies both failure predicates, success state writes, retained storage, and output; the README valid-solution assumption allows omitting the solver and unrelated board search.

## Minimization and alternatives

A PLAY-only excerpt is shorter but cannot establish history/redo effects or retention through its custom executor. The selected executor and its simulation path supply those missing facts. The complete solver, importer, other commands, and direction-search algorithms add no facts to this local modification. Standard optional/nullable checks, value equality, string case conversion and exception propagation are used directly. Reusing the existing separate guards (Quidra/Zig) or splitting the compound guard is smaller and more precise than changing solver storage or the shared error renderer. Error formatting and push-count predicates are included when needed for the requested result text. This is modification analysis only.

The excerpt contains 573 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
