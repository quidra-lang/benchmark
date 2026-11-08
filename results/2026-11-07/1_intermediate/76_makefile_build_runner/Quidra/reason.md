# Task B selection — Quidra

## Answer requirements shared across languages

1. Identify the binding that saves the file table for a dry-run MAKE.
2. Use the binding semantics and one trial file-time write to determine whether saved modification times are independent or aliases that trial updates can overwrite.

## Selected source locations

- `main.qui`: 162, 202, 204, 781, 808

## Evidence and language semantics

saved_files:=files retains the map value under Quidra value semantics. give_time writes the live files map through its mutation call; the saved value retains independent modification times. The files initializer establishes map<string,int>; the .give_time header connects the mutation-authorized helper with the selected call.

## Minimization and alternatives

The saved-table binding/copy, one trial write and its build-time call are enough; omit dependency recursion, command execution and restore logic. Where the save is a custom copy loop its allocation and element copy must both be retained; relying on the saved variable name alone would not establish independence. Deep copying immutable scalar timestamps would add no information. A method call without its writing helper header does not identify which body supplies the trial write. Where needed, retain the container declaration or construction path so the copy semantics are supported by the excerpt; a bare assignment of an untyped container could instead retain a reference. Unrelated build rules remain omitted.

The excerpt contains 64 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
