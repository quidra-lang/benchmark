# Task B selection: 52_polygon_area / C++

For an empty substituted polygon, `p.size()` is zero and the `i < p.size()` test fails before the edge-loop body is entered. The selected next-vertex modulo expression is therefore skipped, so there is no modulo-by-zero evaluation; no element read in that body can occur either. Binding `p` selects the polygon container and does not read a vertex. The initial `twice = 0` and `perimeter = 0` survive, `abs` preserves zero, and fixed precision 1/3 emits `polygon 1: area=0.0 perimeter=0.000`. This is a default result, with no explicit rejection or implicit failure in the selected block.

Selected `main.cpp` lines: 10, 12, 13, 14, 15, 16, 20, 21, 22, 23. Every line is complete, verbatim and in source order.

Minimization: The loop guard proves that the entire body is skipped. The dx/dy declaration and shoelace/perimeter updates add no information about this empty-input path, so all are omitted; retaining a different vertex-read statement would also add tokens without changing that decision. The next-vertex index expression identifies the wrap operation whose evaluation is bypassed. Initialization, container binding, loop entry/exit, post-loop absolute value and formatting are retained to establish the defaults and their displayed forms. Standard vector size/index and stream-format semantics are used without implementation source.

The selected source costs 227 tokens with `metric/tokenizer.py` (previous excerpt: 274). Source analysis only; no Task A program was compiled, built, run or tested.
