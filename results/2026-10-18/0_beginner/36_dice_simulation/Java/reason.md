# Task B selection: 36_dice_simulation / Java

## Common answer requirements

Trace seed 12345 through both generator state updates, derive both dice and their counted sum, and establish update-before-use and reuse of the newly updated state for the second generation.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The first generated state is (12345 × 48271) mod 2147483647 = 595905495; its die is (595905495 mod 6)+1 = 4. The next state is (595905495 × 48271) mod 2147483647 = 1558181227, giving die 2. Thus the first trial increments the bin for sum 6. State assignment precedes each die mapping (or precedes the mapping on each of two loop iterations), so the seed is not itself mapped to die one, and die two uses the next state rather than the first state. Histogram initialization/reporting is unnecessary to identify which occurrence is counted.

The two-iteration die loop updates state on each iteration, then adds that die to sum.

Source: `Main.java`. Selected original lines: 3,6,7,8,9,10,11. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L3: `        long state = 12345;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `            int sum = 0;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `            for (int die = 0; die < 2; die++) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `                state = state * 48271 % 2147483647;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `                sum += (int)(state % 6) + 1;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `            }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L11: `            counts[sum]++;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **126 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **337 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L3: 111 tokens (versus 126); removes `long state = 12345;`.
- Without L6: 114 tokens (versus 126); removes `int sum = 0;`.
- Without L7: 98 tokens (versus 126); removes `for (int die = 0; die < 2; die++) {`.
- Without L8: 94 tokens (versus 126); removes `state = state * 48271 % 2147483647;`.
- Without L9: 102 tokens (versus 126); removes `sum += (int)(state % 6) + 1;`.
- Without L10: 121 tokens (versus 126); removes `}`.
- Without L11: 116 tokens (versus 126); removes `counts[sum]++;`.
