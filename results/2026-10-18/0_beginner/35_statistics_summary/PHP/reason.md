# Task B selection: 35_statistics_summary / PHP

## Common answer requirements

Identify the standard-deviation denominator and change only that normalization from n=11 to n−1=10 before the square root. Preserve the mean, ordered squared-difference accumulation, stdev label, three-decimal half-up presentation and every other statistic.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Replace the divisor inside the standard-deviation square root: hardcoded 11.0 becomes 10.0; a length/size/count expression becomes that count minus one (or the specified 10), retaining any floating-point conversion. Do not change the mean denominator or squared-difference accumulation. The affected expression is already separate from those computations, so their source is unnecessary to locate or explain this edit. Keep the existing rounding/formatting path and labels; the Task B assumptions apply to unchanged presentation.



Source: `main.php`. Selected original lines: 10. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L10: `$deviation = sqrt($squares / count($numbers));` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **20 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **310 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L10: 0 tokens (versus 20); removes `$deviation = sqrt($squares / count($numbers));`.
