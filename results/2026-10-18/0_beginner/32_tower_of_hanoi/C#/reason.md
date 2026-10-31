# Task B selection: 32_tower_of_hanoi / C#

## Common answer requirements

Identify the initial disk-count and peg arguments that must change; establish that the recursive ordering and disk-number/output/count behavior already generalize to five disks; explain total 31 and retained formats.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Change the top-level call disk count from 4 to 5, retaining A as source, C as target, and B as auxiliary. For n>0 the recursion first moves n−1 source-to-auxiliary, prints disk n source-to-target, then moves n−1 auxiliary-to-target. It terminates at n=0; each move contributes one to the returned or shared count. Consequently disks 1..5 require 2^5−1=31 moves, and the original move and final formats already apply. No recursive-body change is needed.



Source: `Program.cs`. Selected original lines: 6,8-11,14. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L6: `static int Hanoi(int n, char source, char target, char auxiliary)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `    if (n == 0) return 0;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `    int count = Hanoi(n - 1, source, auxiliary, target);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `    Console.WriteLine($"move disk {n} from {source} to {target}");` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `    return count + 1 + Hanoi(n - 1, auxiliary, target, source);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `Console.WriteLine($"total moves: {Hanoi(4, 'A', 'C', 'B')}");` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **166 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **200 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L6: 140 tokens (versus 166); removes `static int Hanoi(int n, char source, char target, char auxiliary)`.
- Without L8: 150 tokens (versus 166); removes `if (n == 0) return 0;`.
- Without L9: 140 tokens (versus 166); removes `int count = Hanoi(n - 1, source, auxiliary, target);`.
- Without L10: 135 tokens (versus 166); removes `Console.WriteLine($"move disk {n} from {source} to {target}");`.
- Without L11: 136 tokens (versus 166); removes `return count + 1 + Hanoi(n - 1, auxiliary, target, source);`.
- Without L14: 129 tokens (versus 166); removes `Console.WriteLine($"total moves: {Hanoi(4, 'A', 'C', 'B')}");`.
