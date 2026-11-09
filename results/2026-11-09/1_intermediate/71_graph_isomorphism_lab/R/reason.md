# Task B selection — R

## Answer requirements shared across languages

1. Trace REFINE g with no individualisation arguments from graph lookup through initial ascending degree-color classes.
2. Explain construction of old-color/neighbor-color signatures and each candidate partition,including why replacement is simultaneous rather than sequential vertex feedback.
3. Explain stability testing and round counting,why the final stable attempt is uncounted,and the ascending color/vertex display.

## Selected source locations

- `main.R`: 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 225, 499, 521, 522, 523, 530, 531

## Evidence and language semantics

The registry supplies g. stable ranks row-sum degrees using sorted unique values. All signatures read old colors; fresh is filled separately after signature ordering. Equal class count returns before colors replacement and round increment. Output loops increasing colors,and which returns increasing one-based indices converted to zero-based ids. With no individualisation arguments,the initial degree-based refinement flows directly to this display; no individualize operation runs. Because the signature includes the previous color,classes can split but cannot merge,so unchanged class count means a stable partition even if candidate labels would differ.

## Minimization and alternatives

Retain graph lookup,degree-rank construction,signature/candidate formation,the stability guard before replacement/increment,and ordered display. Known sorting,popcount,container and value-assignment semantics avoid unrelated graph construction and canonicalization. Custom rank/comparison/cell helpers are retained where they establish ordering or class counts. The stable-round guard alone would not establish simultaneous updates or output; the full command dispatcher would add unrelated features.

The excerpt contains 858 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
