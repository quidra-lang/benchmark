# Task B selection: 17_number_bases / Quidra

## Common answer requirements

Locate only hexadecimal uppercase formatting/mapping and explain changing to a–f while leaving decimal/binary/octal, labels/order, zero/prefix/leading-zero rules intact.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

For a hexadecimal format letter X, choose its lowercase x variant; for explicit uppercase/upcase/toUpperCase conversions around a base16 result, remove only that conversion; for an uppercase option/manipulator, select the lowercase setting. For a shared custom digit alphabet, replace only the six A–F entries with a–f: base2 and base8 cannot index those entries, so their digits remain unchanged. Do not add prefixes or width/zero padding, change the zero path, or lowercase the entire output line.

The custom helper indexes alphabet by value%base. At base2/8 that index never reaches10, so changing the six letter entries affects only hex. The caller shows all three actual radices.

Source: `main.qui`. Selected original lines: 1,4,7,13. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `string base_text(int value, int base)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `    string alphabet = "0123456789ABCDEF"` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `        result = alphabet[value % base] + result` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `    print("{value}: bin={base_text(value, 2)} oct={base_text(value, 8)} hex={base_text(value, 16)}{NL}")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **112 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **213 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 96 tokens (versus 112); removes `string base_text(int value, int base)`.
- Without L4: 91 tokens (versus 112); removes `string alphabet = "0123456789ABCDEF"`.
- Without L7: 93 tokens (versus 112); removes `result = alphabet[value % base] + result`.
- Without L13: 56 tokens (versus 112); removes `print("{value}: bin={base_text(value, 2)} oct={base_text(value, 8)} hex={base_text(value, 16)}{NL}")`.
