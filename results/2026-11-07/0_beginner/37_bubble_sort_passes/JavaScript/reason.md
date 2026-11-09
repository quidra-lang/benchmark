## Answer and source evidence

Each pass p compares j and j+1 through the unsorted prefix, swapping only when left>right. In pass 1, 88 passes 41,5,72,36 and reaches the end. The per-pass flag resets false and becomes true on any swap; the pass line prints before the no-swap break. The final order is 5 13 27 36 41 64 72 88; passes make 5,4,2,2,1,0 swaps, so pass 6 is the final printed pass and the total is 14. Original data, all bounds/updates and both print sites are required; closing braces add no facts.

## Selection and minimization

The excerpt contains the complete original source lines listed in their original order. JavaScript uses ordinary Number arithmetic (IEEE 754 double precision); no integer-only static contract is inferred. Blank lines, closing delimiters whose structural role is already determined, and unrelated calculations/output are omitted. Each retained data declaration, binding, operation, condition, or output argument supplies one of the facts above; replacing the selected operations with their callers would conceal those facts, while selecting the entire routine would add unrelated evidence. No Task B modification is implemented.
