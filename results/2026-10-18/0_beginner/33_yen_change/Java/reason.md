# Task B selection: 33_yen_change / Java

## Common answer requirements

Trace 506 through the source denomination order, quotient/remainder transitions, omission of zero quantities, piece accumulation, and exact complete output line.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

For 506, 10000/5000/1000 give zero and do not change remaining. At 500 the quotient is 1 and remainder 6; at 100,50,10 the quotient is zero; at 5 the quotient is 1 and remainder 1; at 1 the quotient is 1 and remainder 0. The positive-count guard omits zero-piece denominations. Adding the three positive quantities gives 3. The exact line is `506 yen: 500x1 5x1 1x1 (3 pieces)` followed by newline.



Source: `Main.java`. Selected original lines: 6,7,8,9,10,11,12,13,14,15,16,17,18. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L6: `        int[] denominations = {10000, 5000, 1000, 500, 100, 50, 10, 5, 1};` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `        for (int amount : new int[]{3780, 15420, 99999, 506, 48263}) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `            int remaining = amount, total = 0;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `            List<String> parts = new ArrayList<>();` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `            for (int face : denominations) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `                int count = remaining / face;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `                remaining %= face;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `                total += count;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `                if (count > 0) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `                    parts.add(face + "x" + count);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `                }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L17: `            }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L18: `            System.out.println(amount + " yen: " + String.join(" ", parts) + " (" + total + " pieces)");` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **307 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **361 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L6: 253 tokens (versus 307); removes `int[] denominations = {10000, 5000, 1000, 500, 100, 50, 10, 5, 1};`.
- Without L7: 256 tokens (versus 307); removes `for (int amount : new int[]{3780, 15420, 99999, 506, 48263}) {`.
- Without L8: 288 tokens (versus 307); removes `int remaining = amount, total = 0;`.
- Without L9: 285 tokens (versus 307); removes `List<String> parts = new ArrayList<>();`.
- Without L10: 290 tokens (versus 307); removes `for (int face : denominations) {`.
- Without L11: 290 tokens (versus 307); removes `int count = remaining / face;`.
- Without L12: 296 tokens (versus 307); removes `remaining %= face;`.
- Without L13: 296 tokens (versus 307); removes `total += count;`.
- Without L14: 291 tokens (versus 307); removes `if (count > 0) {`.
- Without L15: 284 tokens (versus 307); removes `parts.add(face + "x" + count);`.
- Without L16: 301 tokens (versus 307); removes `}`.
- Without L17: 302 tokens (versus 307); removes `}`.
- Without L18: 252 tokens (versus 307); removes `System.out.println(amount + " yen: " + String.join(" ", parts) + " (" + total + " pieces)");`.
