# Task B selection — R

## Answer requirements shared across languages

1. Identify the binding that saves the file table for a dry-run MAKE.
2. Use the binding semantics and one trial file-time write to determine whether saved modification times are independent or aliases that trial updates can overwrite.

## Selected source locations

- `main.R`: 15, 17, 462, 464, 585, 633, 691, 698

## Evidence and language semantics

R list/vector values use copy-on-modification semantics. saved_files <- state$files retains the old table value even though state itself is an environment; the trial replacement changes the files field value and leaves the saved times intact. The input files value is constructed as a list and passed to make_workbench, which stores it in state$files. This establishes list value semantics rather than an aliased environment; new_time writes the live list slot and leaves saved_files unchanged.

## Minimization and alternatives

The saved-table binding/copy, one trial write and its build-time call are enough; omit dependency recursion, command execution and restore logic. Where the save is a custom copy loop its allocation and element copy must both be retained; relying on the saved variable name alone would not establish independence. Deep copying immutable scalar timestamps would add no information. A method call without its writing helper header does not identify which body supplies the trial write. Where needed, retain the container declaration or construction path so the copy semantics are supported by the excerpt; a bare assignment of an untyped container could instead retain a reference. Unrelated build rules remain omitted.

The excerpt contains 118 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
