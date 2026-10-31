# Task B selection: 47_student_records / R

## Common answer requirements

Locate competition-rank update and its initialization/change detector; explain dense distinct-score ranks with tied totals sharing rank and no skipped rank, preserving sort, names, averages and output.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Keep rank initialized to0 and increment it by1 exactly when the next total differs from the previous distinct total (including the first record). Replace assignment from positional index/position+1 with this increment; retain the existing total-change guard and previous-total update. Equal totals leave rank unchanged. Hence 270,251,251,199 receive1,2,2,3. The sorted order and formatting are unaffected and need no changes. For a vectorized rank implementation, replace the competition-rank construction with each total’s index in descending distinct totals, keeping the resulting ranks aligned to original student indices for the existing ordered output.

rank(-totals,ties.method="min") produces competition ranks. Use a dense mapping against sorted unique totals; L8 shows ranks[ordered], so preserve original-index alignment rather than supplying a vector already reordered by rank.

Source: `main.R`. Selected original lines: 5,8. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L5: `ranks <- rank(-totals, ties.method = "min")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `  ranks[ordered], names[ordered], totals[ordered], totals[ordered] / 3` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **49 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **251 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L5: 28 tokens (versus 49); removes `ranks <- rank(-totals, ties.method = "min")`.
- Without L8: 21 tokens (versus 49); removes `ranks[ordered], names[ordered], totals[ordered], totals[ordered] / 3`.
