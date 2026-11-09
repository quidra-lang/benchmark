# Task B selection — J

## Answer requirements shared across languages

1. Identify the VARIANCE missing-baseline guard and exact output-message expression to revise to error: baseline required.
2. Preserve earlier no-tasks/cycle errors and preserve acceptance of any existing baseline, including an unchanged one.

## Selected source locations

- `main.ijs`: 111, 112, 113, 114, 507, 511, 654

## Evidence and language semantics

The VARIANCE guard uses -.Baseline-:a: (not the absent sentinel). Change only the message argument from no baseline to baseline required in check; the selected formatter/catch supplies the existing error: prefix. Earlier no-tasks and cycle failures remain before this guard. Presence is the condition, so a stored baseline remains valid even when unchanged.

## Minimization and alternatives

The missing-state guard and its message are the actual change site; earlier failure guards and the existing error prefix establish required ordering/representation. No baseline contents, comparison algorithm, task mutation or scheduling calculations are needed. Replacing the whole baseline test would be a larger and behavior-changing alternative.

The excerpt contains 112 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
