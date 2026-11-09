# Task B selection — TypeScript

## Answer requirements shared across languages

1. Identify the binding that saves the file table for a dry-run MAKE.
2. Use the binding semantics and one trial file-time write to determine whether saved modification times are independent or aliases that trial updates can overwrite.

## Selected source locations

- `main.ts`: 140, 163, 164, 680, 775

## Evidence and language semantics

new Map(this.files) makes an independent mapping of numeric times. touch sets the live map only; the saved map retains its original values. The files initializer establishes a standard Map<string,number>, and touch identifies the body containing the selected set call.

## Minimization and alternatives

The saved-table binding/copy, one trial write and its build-time call are enough; omit dependency recursion, command execution and restore logic. Where the save is a custom copy loop its allocation and element copy must both be retained; relying on the saved variable name alone would not establish independence. Deep copying immutable scalar timestamps would add no information. A method call without its writing helper header does not identify which body supplies the trial write. Where needed, retain the container declaration or construction path so the copy semantics are supported by the excerpt; a bare assignment of an untyped container could instead retain a reference. Unrelated build rules remain omitted.

The excerpt contains 105 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
