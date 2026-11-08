# Task B selection — PHP

## Answer requirements shared across languages

1. Identify the binding that saves the file table for a dry-run MAKE.
2. Use the binding semantics and one trial file-time write to determine whether saved modification times are independent or aliases that trial updates can overwrite.

## Selected source locations

- `main.php`: 636, 797, 849

## Evidence and language semantics

PHP array assignment has value/copy-on-write semantics. $savedFiles=$this->files retains old numeric times; newTime overwrites a live array element rather than mutating a shared object.

## Minimization and alternatives

The saved-table binding/copy, one trial write and its build-time call are enough; omit dependency recursion, command execution and restore logic. Where the save is a custom copy loop its allocation and element copy must both be retained; relying on the saved variable name alone would not establish independence. Deep copying immutable scalar timestamps would add no information.

The excerpt contains 51 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
