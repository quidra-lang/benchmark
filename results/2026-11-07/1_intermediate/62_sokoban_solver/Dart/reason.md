# Task B selection — Dart

## Answer requirements shared across languages

1. Distinguish absent stored solution from a stored solution associated with another current position, and locate the ordered error guards before any execution.
2. Trace the successful PLAY path through stored notation, movement execution, current-position/history updates and conditional redo clearing.
3. Explain result text and stored-solution retention, and split only the two failure messages without executing moves, discarding the solution, or changing successful behavior.

## Selected source locations

- `main.dart`: 128, 130, 199, 200, 201, 202, 203, 204, 679, 680, 681, 682, 683, 684, 685, 686, 687, 688, 689, 690, 692, 695, 696, 697, 698, 699, 700, 701, 702, 1023, 1024, 1025, 1026, 1027, 1028, 1029, 1030, 1031, 1032, 1033, 1106

## Evidence and language semantics

A local stored reference is checked for null and position equality before accessing notation. Split that guard into two throws; simulate/takeSteps retain solution and update only the current position and move history. For a valid stored solution at the current position, the selected loop executes its notation in order and the commit helper appends the executed move letters; redo clears only when at least one letter was executed. The played result reports pushes and notation length. No selected success path deletes the stored solution. On either new failure, the early return/exception precedes every movement and history update. The excerpt alone identifies both failure predicates, success state writes, retained storage, and output; the README valid-solution assumption allows omitting the solver and unrelated board search.

## Minimization and alternatives

A PLAY-only excerpt is shorter but cannot establish history/redo effects or retention through its custom executor. The selected executor and its simulation path supply those missing facts. The complete solver, importer, other commands, and direction-search algorithms add no facts to this local modification. Standard optional/nullable checks, value equality, string case conversion and exception propagation are used directly. Reusing the existing separate guards (Quidra/Zig) or splitting the compound guard is smaller and more precise than changing solver storage or the shared error renderer. Error formatting and push-count predicates are included when needed for the requested result text. This is modification analysis only.

The excerpt contains 591 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
