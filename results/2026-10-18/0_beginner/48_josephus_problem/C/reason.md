# Task B selection: 48_josephus_problem / C

## Common answer requirements

Trace first three removals for n=7,k=3, explain advancement/resumption and wraparound using remaining-circle representation and derive removal order.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

People begin [1,2,3,4,5,6,7] with zero-based index0. First index=(0+3−1)%7=2 removes3, leaving [1,2,4,5,6,7]; the same index now points at4, where counting resumes. Next index=(2+2)%6=4 removes6, leaving [1,2,4,5,7]; index4 now refers to7. The third count is7,1,2 across the wrap, so index=(4+2)%5=1 removes2. Thus the first three removals are3,6,2. Removal compacts the remaining sequence without resetting index; modulo its current length handles wraparound. One-based containers use index+1 only at lookup/removal, not in the circular arithmetic.

The inner shift copies every successor over its removed predecessor and len-- shrinks the live circle; both are required to derive the new next person.

Source: `main.c`. Selected original lines: 4,6,7,8,9,11,12,13,15,16,17. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L4: `    int cases[][2] = {{7, 3}, {10, 2}, {41, 3}};` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `        int n = cases[c][0], k = cases[c][1];` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `        int people[41], len = n, index = 0, last = 0;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `        for (int i = 0; i < n; i++)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `            people[i] = i + 1;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `        while (len) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `            index = (index + k - 1) % len;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `            last = people[index];` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `            for (int i = index; i < len - 1; i++)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `                people[i] = people[i + 1];` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `            len--;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **248 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **368 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L4: 209 tokens (versus 248); removes `int cases[][2] = {{7, 3}, {10, 2}, {41, 3}};`.
- Without L6: 218 tokens (versus 248); removes `int n = cases[c][0], k = cases[c][1];`.
- Without L7: 216 tokens (versus 248); removes `int people[41], len = n, index = 0, last = 0;`.
- Without L8: 223 tokens (versus 248); removes `for (int i = 0; i < n; i++)`.
- Without L9: 231 tokens (versus 248); removes `people[i] = i + 1;`.
- Without L11: 238 tokens (versus 248); removes `while (len) {`.
- Without L12: 224 tokens (versus 248); removes `index = (index + k - 1) % len;`.
- Without L13: 235 tokens (versus 248); removes `last = people[index];`.
- Without L15: 218 tokens (versus 248); removes `for (int i = index; i < len - 1; i++)`.
- Without L16: 227 tokens (versus 248); removes `people[i] = people[i + 1];`.
- Without L17: 241 tokens (versus 248); removes `len--;`.
