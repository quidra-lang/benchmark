# Task B selection: 25_electricity_bill / Quidra

## Common answer requirements

Trace the supplied usages 120 and 300 through the basic charge and marginal tiers; compute each applicable tier quantity and amount; identify the bounds/branches preventing full-usage higher-rate charging. The question itself supplies the two usage inputs, so unrelated household data and output formatting are not required.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

For 120 kWh, the first tier contributes 120 × 30 = 3600 and the basic charge 900 gives 4500 yen. For 300 kWh, the first tier remains capped at 120, the second tier is 300 − 120 = 180 at 36 (6480), and the basic charge gives 10980 yen. No positive quantity lies above 300. A minimum/clamp expression caps each marginal portion; conditional implementations enter only the appropriate usage branch. These are charges on portions, not multiplication of the whole 300 by 36.

Only the <=120 and <=300 branches can apply to these inputs. The unused else branch need not be read. Each selected branch condition and charge statement is needed to distinguish the two traces.

Source: `main.qui`. Selected original lines: 6-10. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L6: `    int bill = 900` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `    if usage <= 120` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `        bill += usage * 30` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `    elif usage <= 300` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `        bill += 120 * 30 + (usage - 120) * 36` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **78 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **287 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L6: 67 tokens (versus 78); removes `int bill = 900`.
- Without L7: 67 tokens (versus 78); removes `if usage <= 120`.
- Without L8: 65 tokens (versus 78); removes `bill += usage * 30`.
- Without L9: 67 tokens (versus 78); removes `elif usage <= 300`.
- Without L10: 46 tokens (versus 78); removes `bill += 120 * 30 + (usage - 120) * 36`.
