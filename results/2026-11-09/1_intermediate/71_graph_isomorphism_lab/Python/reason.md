# Task B selection — Python

## Answer requirements shared across languages

1. Trace REFINE g with no individualisation arguments from graph lookup through initial ascending degree-color classes.
2. Explain construction of old-color/neighbor-color signatures and each candidate partition,including why replacement is simultaneous rather than sequential vertex feedback.
3. Explain stability testing and round counting,why the final stable attempt is uncounted,and the ascending color/vertex display.

## Selected source locations

- `main.py`: 313, 314, 315, 316, 317, 318, 319, 320, 321, 322, 323, 324, 325, 326, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 348, 349, 350, 351, 352, 557, 560, 566, 567, 568, 569

## Evidence and language semantics

The graph dictionary supplies graph. degree_colouring ranks adjacency lengths using sorted distinct keys. Every signature reads old colours; rank makes a new refined list. Equal maximum color returns before rebinding and increment. cells_of appends vertices in enumerate order,and display enumerates cells. With no individualisation arguments,the initial degree-based refinement flows directly to this display; no individualize operation runs. Because the signature includes the previous color,classes can split but cannot merge,so unchanged class count means a stable partition even if candidate labels would differ.

## Minimization and alternatives

Retain graph lookup,degree-rank construction,signature/candidate formation,the stability guard before replacement/increment,and ordered display. Known sorting,popcount,container and value-assignment semantics avoid unrelated graph construction and canonicalization. Custom rank/comparison/cell helpers are retained where they establish ordering or class counts. The stable-round guard alone would not establish simultaneous updates or output; the full command dispatcher would add unrelated features.

The excerpt contains 440 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
