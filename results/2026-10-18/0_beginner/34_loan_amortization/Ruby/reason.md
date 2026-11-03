# Task B selection: 34_loan_amortization / Ruby

## Common answer requirements

Explain the final-month payment cap when balance+interest<50000, the principal and new balance relationships, inclusion of the actual payment in total paid, and termination after that accumulation.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

When balance+interest is below 50000, the minimum/conditional selects exactly balance+interest as payment. Principal is payment−interest, so it equals the full remaining balance; subtracting it makes balance zero. The same actual payment, including that month’s interest, is added to total paid before control returns to the positive-balance loop condition. That condition then fails, so no extra full payment is charged. The original balance, month numbering, interest-total accumulation and reporting format are unnecessary to this conditional final-month explanation.

positive? is the loop predicate and Array#min implements the payment cap; integer division details are immaterial to this conditional final-month relationship.

Source: `main.rb`. Selected original lines: 3,6-8,10. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L3: `while balance.positive?` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `  payment = [50000, balance + interest].min` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `  principal = payment - interest` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `  balance -= principal` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `  total_paid += payment` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **55 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **178 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L3: 48 tokens (versus 55); removes `while balance.positive?`.
- Without L6: 34 tokens (versus 55); removes `payment = [50000, balance + interest].min`.
- Without L7: 44 tokens (versus 55); removes `principal = payment - interest`.
- Without L8: 48 tokens (versus 55); removes `balance -= principal`.
- Without L10: 46 tokens (versus 55); removes `total_paid += payment`.
