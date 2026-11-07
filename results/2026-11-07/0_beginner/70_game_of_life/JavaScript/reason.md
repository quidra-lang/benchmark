## Answer and source evidence

A fresh nextBoard/following is built separately while each cell counts live neighbors only from current board. Offsets -1..1 skip the center; && evaluates left-to-right, so at corner (0,0), r=-1 fails r>=0 before board[-1][c] access. Birth requires three neighbors; an existing live cell survives with two. Each result is written to the separate next board, and current board is replaced only after every row/cell is complete, so newly computed cells cannot affect later counts. Initialization, loops, guarded access, rule, result construction and final replacement are all needed; generation printing and later generations are unrelated.

## Selection and minimization

The excerpt contains the complete original source lines listed in their original order. JavaScript uses ordinary Number arithmetic (IEEE 754 double precision); no integer-only static contract is inferred. Blank lines, closing delimiters whose structural role is already determined, and unrelated calculations/output are omitted. Each retained data declaration, binding, operation, condition, or output argument supplies one of the facts above; replacing the selected operations with their callers would conceal those facts, while selecting the entire routine would add unrelated evidence. No Task B modification is implemented.
