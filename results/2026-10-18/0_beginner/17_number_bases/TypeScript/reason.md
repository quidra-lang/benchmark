# Task B selection: 17_number_bases / TypeScript

## Common answer requirements

Locate only hexadecimal uppercase formatting/mapping and explain changing to a–f while leaving decimal/binary/octal, labels/order, zero/prefix/leading-zero rules intact.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

For a hexadecimal format letter X, choose its lowercase x variant; for explicit uppercase/upcase/toUpperCase conversions around a base16 result, remove only that conversion; for an uppercase option/manipulator, select the lowercase setting. For a shared custom digit alphabet, replace only the six A–F entries with a–f: base2 and base8 cannot index those entries, so their digits remain unchanged. Do not add prefixes or width/zero padding, change the zero path, or lowercase the entire output line.



Source: `main.ts`. Selected original lines: 2. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L2: `  console.log(`${n}: bin=${n.toString(2)} oct=${n.toString(8)} hex=${n.toString(16).toUpperCase()}`);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **60 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **107 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L2: 0 tokens (versus 60); removes `console.log(`${n}: bin=${n.toString(2)} oct=${n.toString(8)} hex=${n.toString(16).toUpperCase()}`);`.
