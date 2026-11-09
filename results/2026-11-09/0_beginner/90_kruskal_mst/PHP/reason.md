## Answer and source evidence

Sorting by weight and Union-Find root comparison accepts G-H 2, C-E 3, A-C 4, D-E 5, A-B 7, F-G 8, E-H 10 in that output order. Weight 5 connects distinct components; weight 6 (C-D) is rejected because C and D are already connected. B-C 9 is the other rejection. Accepted count reaches 7 at E-H 10 and breaks immediately, leaving weights 11,12,14,16 unexamined. Total weight is 39 and skipped is 2. Endpoint sorting normalizes C-A, E-D and H-E labels. Edge data, initialized disjoint sets, root operation, accept/reject/counter/stop and output stages are needed for the complete trace.

## Selection and minimization

The excerpt contains the complete original source lines listed in their original order. PHP array/string/arithmetic and formatting operations are interpreted with their standard runtime semantics; no stronger static invariant is inferred. Blank lines, closing delimiters whose structural role is already determined, and unrelated calculations/output are omitted. Each retained data declaration, binding, operation, condition, or output argument supplies one of the facts above; replacing the selected operations with their callers would conceal those facts, while selecting the entire routine would add unrelated evidence. No Task B modification is implemented.
