# Task B selection: 32_tower_of_hanoi / Dart

## Common answer requirements

Identify the initial disk-count and peg arguments that must change; establish that the recursive ordering and disk-number/output/count behavior already generalize to five disks; explain total 31 and retained formats.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Change the top-level call disk count from 4 to 5, retaining A as source, C as target, and B as auxiliary. For n>0 the recursion first moves n−1 source-to-auxiliary, prints disk n source-to-target, then moves n−1 auxiliary-to-target. It terminates at n=0; each move contributes one to the returned or shared count. Consequently disks 1..5 require 2^5−1=31 moves, and the original move and final formats already apply. No recursive-body change is needed.

The nested helper updates the captured count once per move. Retain its counter mechanism; only the invocation changes.

Source: `main.dart`. Selected original lines: 3-8,11. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L3: `  void hanoi(int n, String source, String target, String auxiliary) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `    if (n == 0) return;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `    hanoi(n - 1, source, auxiliary, target);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `    print('move disk $n from $source to $target');` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `    count++;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `    hanoi(n - 1, auxiliary, target, source);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `  hanoi(4, 'A', 'C', 'B');` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **132 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **171 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L3: 105 tokens (versus 132); removes `void hanoi(int n, String source, String target, String auxiliary) {`.
- Without L4: 118 tokens (versus 132); removes `if (n == 0) return;`.
- Without L5: 112 tokens (versus 132); removes `hanoi(n - 1, source, auxiliary, target);`.
- Without L6: 108 tokens (versus 132); removes `print('move disk $n from $source to $target');`.
- Without L7: 127 tokens (versus 132); removes `count++;`.
- Without L8: 112 tokens (versus 132); removes `hanoi(n - 1, auxiliary, target, source);`.
- Without L11: 110 tokens (versus 132); removes `hanoi(4, 'A', 'C', 'B');`.
