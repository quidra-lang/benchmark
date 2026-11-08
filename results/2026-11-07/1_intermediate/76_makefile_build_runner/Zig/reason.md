# Task B selection — Zig

## Answer requirements shared across languages

1. Identify the binding that saves the file table for a dry-run MAKE.
2. Use the binding semantics and one trial file-time write to determine whether saved modification times are independent or aliases that trial updates can overwrite.

## Selected source locations

- `main.zig`: 663, 665, 728, 729, 730, 731, 732, 879

## Evidence and language semantics

The save path constructs an empty StringHashMap and puts each numeric value into distinct map storage. Trial touch writes self.files. Keys may share text storage, but stored modification times do not alias. The helper header connects the selected trial invocation with the shown file-time write.

## Minimization and alternatives

The saved-table binding/copy, one trial write and its build-time call are enough; omit dependency recursion, command execution and restore logic. Where the save is a custom copy loop its allocation and element copy must both be retained; relying on the saved variable name alone would not establish independence. Deep copying immutable scalar timestamps would add no information. A method call without its writing helper header does not identify which body supplies the trial write. Where needed, retain the container declaration or construction path so the copy semantics are supported by the excerpt; a bare assignment of an untyped container could instead retain a reference. Unrelated build rules remain omitted.

The excerpt contains 186 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
