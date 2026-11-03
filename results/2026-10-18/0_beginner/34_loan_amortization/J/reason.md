# Task B selection: 34_loan_amortization / J

## Common answer requirements

Explain the final-month payment cap when balance+interest<50000, the principal and new balance relationships, inclusion of the actual payment in total paid, and termination after that accumulation.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

When balance+interest is below 50000, the minimum/conditional selects exactly balance+interest as payment. Principal is payment−interest, so it equals the full remaining balance; subtracting it makes balance zero. The same actual payment, including that month’s interest, is added to total paid before control returns to the positive-balance loop condition. That condition then fails, so no extra full payment is charged. The original balance, month numbering, interest-total accumulation and reporting format are unnecessary to this conditional final-month explanation.

<. between payment cap and amount due is minimum. The assignment order establishes that totalpaid is updated after balance becomes zero but before the next while test.

Source: `main.ijs`. Selected original lines: 6,9-11,13. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L6: `  while. balance>0 do.` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `    payment =. 50000 <. balance+interest` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `    principal =. payment-interest` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `    balance =. balance-principal` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `    totalpaid =. totalpaid+payment` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **53 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **215 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L6: 44 tokens (versus 53); removes `while. balance>0 do.`.
- Without L9: 36 tokens (versus 53); removes `payment =. 50000 <. balance+interest`.
- Without L10: 44 tokens (versus 53); removes `principal =. payment-interest`.
- Without L11: 44 tokens (versus 53); removes `balance =. balance-principal`.
- Without L13: 44 tokens (versus 53); removes `totalpaid =. totalpaid+payment`.
