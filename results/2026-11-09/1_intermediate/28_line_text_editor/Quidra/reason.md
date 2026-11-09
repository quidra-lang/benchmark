# Task B selection — Quidra

## Answer requirements shared across languages

1. Locate command-name recognition and dispatch needed to accept the exact word redo as another spelling of the existing redo operation.
2. Preserve r with a file argument on the read path, the existing redo count/default behavior, and rejection of addresses on redo.

## Selected source locations

- `main.qui`: 281, 282, 299, 300, 301, 302, 361, 362, 363, 770, 771, 799, 800, 801, 802, 803

## Evidence and language semantics

parse_action splits first/argument and constructs Kind.Redo or Kind.Read; address_kind and transfer_history consume the resulting Action kind. Recognize the whole word redo before the current first-character split, constructing the existing redo command with its default count. Keep the present r distinction between empty/numeric count and filename untouched. Returning the existing redo command identity feeds the selected redo dispatch and zero-address classification, so an addressed redo still takes the same unexpected-address rejection.

## Minimization and alternatives

The recognition split, r branching, redo dispatch and no-address rejection are all necessary. History movement and file reading implementations are unaffected and can be omitted. Rewriting every r-prefixed command would also rewrite filenames; the smaller precise change is an exact-word recognition arm before character dispatch. No modified source is included.

The excerpt contains 294 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
