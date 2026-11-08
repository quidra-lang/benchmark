# Task B selection — Quidra

## Answer requirements shared across languages

1. Trace REFINE g with no individualisation arguments from graph lookup through initial ascending degree-color classes.
2. Explain construction of old-color/neighbor-color signatures and each candidate partition,including why replacement is simultaneous rather than sequential vertex feedback.
3. Explain stability testing and round counting,why the final stable attempt is uncounted,and the ascending color/vertex display.

## Selected source locations

- `main.qui`: 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 53, 54, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 161, 162, 167, 168, 671, 689, 695, 696, 697, 698

## Evidence and language semantics

get_graph supplies graph. degree_colors ranks degrees by counts of distinct lower values. Signatures are built entirely from colors; representatives identify unique signatures,and next ranks them through lex_less. Stable representative count returns before replacing colors and incrementing rounds. cells and display preserve ascending colors and vertex indices. With no individualisation arguments,the initial degree-based refinement flows directly to this display; no individualize operation runs. Because the signature includes the previous color,classes can split but cannot merge,so unchanged class count means a stable partition even if candidate labels would differ.

## Minimization and alternatives

Retain graph lookup,degree-rank construction,signature/candidate formation,the stability guard before replacement/increment,and ordered display. Known sorting,popcount,container and value-assignment semantics avoid unrelated graph construction and canonicalization. Custom rank/comparison/cell helpers are retained where they establish ordering or class counts. The stable-round guard alone would not establish simultaneous updates or output; the full command dispatcher would add unrelated features.

The excerpt contains 849 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
