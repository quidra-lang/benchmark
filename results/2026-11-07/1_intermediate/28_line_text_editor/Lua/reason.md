# Task B selection — Lua

## Answer requirements shared across languages

1. Locate command-name recognition and dispatch needed to accept the exact word redo as another spelling of the existing redo operation.
2. Preserve r with a file argument on the read path, the existing redo count/default behavior, and rejection of addresses on redo.

## Selected source locations

- `main.lua`: 194, 205, 206, 207, 208, 209, 261, 571, 572, 573, 574, 575, 646, 647

## Evidence and language semantics

The parser splits first/argument and rewrites result.kind to redo or read; no_address and the history branch consume that kind. Recognize the whole word redo before the current first-character split, constructing the existing redo command with its default count. Keep the present r distinction between empty/numeric count and filename untouched. Returning the existing redo command identity feeds the selected redo dispatch and zero-address classification, so an addressed redo still takes the same unexpected-address rejection.

## Minimization and alternatives

The recognition split, r branching, redo dispatch and no-address rejection are all necessary. History movement and file reading implementations are unaffected and can be omitted. Rewriting every r-prefixed command would also rewrite filenames; the smaller precise change is an exact-word recognition arm before character dispatch. No modified source is included.

The excerpt contains 363 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
