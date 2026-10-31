# Task B selection: 48_josephus_problem / Quidra

## Common answer requirements

Trace first three removals for n=7,k=3, explain advancement/resumption and wraparound using remaining-circle representation and derive removal order.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

People begin [1,2,3,4,5,6,7] with zero-based index0. First index=(0+3−1)%7=2 removes3, leaving [1,2,4,5,6,7]; the same index now points at4, where counting resumes. Next index=(2+2)%6=4 removes6, leaving [1,2,4,5,7]; index4 now refers to7. The third count is7,1,2 across the wrap, so index=(4+2)%5=1 removes2. Thus the first three removals are3,6,2. Removal compacts the remaining sequence without resetting index; modulo its current length handles wraparound. One-based containers use index+1 only at lookup/removal, not in the circular arithmetic.

The comprehension retains all original remaining people except the chosen index and preserves their order; index itself is not reset.

Source: `main.qui`. Selected original lines: 1-6,9-11,13. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `int[][] cases = [[7, 3], [10, 2], [41, 3]]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L2: `for int[] pair = cases[]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L3: `    int n = pair[0]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `    int k = pair[1]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `    int[] people = 1:n` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `    int index = 0` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `    while len(people) > 0` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `        index = (index + k - 1) % int(len(people))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `        survivor = people[index]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `        people = [for nat i < len(people) if int(i) != index then people[i]]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **179 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **237 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 146 tokens (versus 179); removes `int[][] cases = [[7, 3], [10, 2], [41, 3]]`.
- Without L2: 167 tokens (versus 179); removes `for int[] pair = cases[]`.
- Without L3: 167 tokens (versus 179); removes `int n = pair[0]`.
- Without L4: 167 tokens (versus 179); removes `int k = pair[1]`.
- Without L5: 167 tokens (versus 179); removes `int[] people = 1:n`.
- Without L6: 170 tokens (versus 179); removes `int index = 0`.
- Without L9: 167 tokens (versus 179); removes `while len(people) > 0`.
- Without L10: 151 tokens (versus 179); removes `index = (index + k - 1) % int(len(people))`.
- Without L11: 168 tokens (versus 179); removes `survivor = people[index]`.
- Without L13: 141 tokens (versus 179); removes `people = [for nat i < len(people) if int(i) != index then people[i]]`.
