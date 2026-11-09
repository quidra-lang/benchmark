## Answer and source evidence

Rename state/$state introduction at seed 42 and both left- and right-hand references in the two MINSTD recurrence assignments to rng_state. The random reads state%5+1 for the interarrival increment and state%7+2 for service must follow the rename too. arrival/$arrival is a separate binding initialized to 0 and accumulates increments rather than holding the recurrence state, so its name and references stay unchanged. The introduction and all recurrence/read sites form the complete minimal name-resolution evidence; teller assignment and customer output are unrelated.

## Selection and minimization

The excerpt contains the complete original source lines listed in their original order. JavaScript uses ordinary Number arithmetic (IEEE 754 double precision); no integer-only static contract is inferred. Blank lines, closing delimiters whose structural role is already determined, and unrelated calculations/output are omitted. Each retained data declaration, binding, operation, condition, or output argument supplies one of the facts above; replacing the selected operations with their callers would conceal those facts, while selecting the entire routine would add unrelated evidence. No Task B modification is implemented.
