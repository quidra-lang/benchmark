# Task B selection — 86_convex_hull / Quidra

Ascending x then y starts the lower scan at (-6,-2), (-6,1), (-6,3); the third point gives cross product zero and removes (-6,1). In the reverse scan the last three points are (-6,3), (-6,1), (-6,-2); the same nonpositive test removes the middle again. Keeping only positive turns eliminates collinear interior points. The join takes the ascending lower chain followed by the reverse upper chain with the last point of each omitted, so the shared extrema appear once and the hull starts at (-6,-2) counterclockwise. The retained sort, cross product and join carry these facts without area or presentation code.

Selected complete source lines: 1, 3, 4, 6, 7, 8, 9, 10, 11, 12, 14, 15, 16, 18, 19, 20, 21, 22, 23.

With the benchmark tokenizer, this selection measures 395 tokens; the previous selection measured 409. The full source is 561 tokens.

The `:=` bindings infer their static types from their initializers under the current Core literal defaults.

Current measurement with unchanged `metric/tokenizer.py`: Task A 561; Task B 395.

Measurement: Task A 561; Task B 395. Tokenizer: metric/tokenizer.py, unchanged.
