# Task B selection — J

## Answer requirements shared across languages

1. Trace REFINE g with no individualisation arguments from graph lookup through initial ascending degree-color classes.
2. Explain construction of old-color/neighbor-color signatures and each candidate partition,including why replacement is simultaneous rather than sequential vertex feedback.
3. Explain stability testing and round counting,why the final stable attempt is uncounted,and the ascending color/vertex display.

## Selected source locations

- `main.ijs`: 37, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 393, 561, 582, 589, 590, 591

## Evidence and language semantics

getGraph resolves the name. degreeColors ranks row sums by lexLess counts of unique lower keys. refine constructs every old-color signature,rankKeys makes next,and equal unique counts returns old colors,rounds before rebinding/increment. cells uses ascending color and I. gives increasing vertex indices. With no individualisation arguments,the initial degree-based refinement flows directly to this display; no individualize operation runs. Because the signature includes the previous color,classes can split but cannot merge,so unchanged class count means a stable partition even if candidate labels would differ.

## Minimization and alternatives

Retain graph lookup,degree-rank construction,signature/candidate formation,the stability guard before replacement/increment,and ordered display. Known sorting,popcount,container and value-assignment semantics avoid unrelated graph construction and canonicalization. Custom rank/comparison/cell helpers are retained where they establish ordering or class counts. The stable-round guard alone would not establish simultaneous updates or output; the full command dispatcher would add unrelated features.

The excerpt contains 505 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
