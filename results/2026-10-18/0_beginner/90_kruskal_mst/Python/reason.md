# Task B selection: 90_kruskal_mst / Python

## Common answer requirements

Trace the weight-5 and weight-6 decisions, the final accepted edge and stopping rule, and distinguish examined cycle edges from unexamined edges.

## Source evidence and minimization

The selected edges through weight 10, ascending sort, path-compressing find, root comparison and union establish the component trace. Weight 5 joins components; weight 6 has equal roots and increments skipped. Weight 10 completes seven accepted edges for eight vertices and breaks before later edges. The separate weight-14 record is unnecessary, just like higher unexamined edges omitted in Quidra. The selected break and the fact skipped increments only in the examined equal-root branch establish why unexamined edges do not contribute.

Selected original source lines: L1, L2, L3, L4, L5, L7, L8, L9, L12, L14, L15, L17, L20, L21, L22, L23, L24, L27, L28, L29, L30, L31, L32, L33, L34, L38, L39.
Every selected line is complete, verbatim and in source order. Alternative complete
source and contiguous-context selections retain unrelated information; the removed
input records or independent operations add no required fact. This is a reviewed
sufficient minimized candidate, not a proof of a global mathematical minimum.
Language and documented library semantics are available as prior knowledge.

Task B: 367 tokens under the unchanged metric/tokenizer.py. Task A is unchanged
by this evidence correction.
