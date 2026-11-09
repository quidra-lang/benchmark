# Task B selection — Ruby

## Answer requirements shared across languages

1. Locate the ordered UPDATE assignment representation, preserve table lookup, left-to-right target-column lookup and duplicate rejection, then each expression check and its destination-type check, then WHERE validation.
2. Freeze target membership from original table rows and their original values; evaluate each selected row into a separate candidate row from left to right, making later expressions read the already-updated candidate.
3. Keep final constraints in target row order, NOT NULL by column order before primary-key uniqueness against the entire final candidate table, and publish only after every constraint succeeds.
4. Preserve the original table on any failure and retain the number of target rows including unchanged rows, with the singular/plural rows-updated output; explain the ownership/copy boundary using source and language semantics.

## Selected source locations

- `main.rb`: 52, 53, 54, 55, 56, 125, 126, 127, 128, 129, 327, 328, 329, 330, 331, 332, 333, 334, 335, 350, 351, 352, 353, 354, 355, 356, 357, 358, 359, 360, 361, 362, 363, 364, 365, 366, 367, 368, 369, 370, 371, 372, 373, 374, 375, 376, 377, 378, 379, 382, 383, 384, 385, 386, 387, 388, 389, 390, 391, 424, 425, 426, 429, 470, 471, 472, 513, 514, 515, 532, 533, 534, 535, 536, 537, 538, 539, 540, 541, 542, 543, 544, 545, 546, 547, 548, 549, 550, 551, 552, 553, 554, 599, 600, 601, 602, 603, 604, 605, 606, 607, 608, 609, 610, 611, 612, 613, 614, 615, 616, 617, 618, 619, 620, 621

## Evidence and language semantics

SET a=b, b=a on a row (a=1,b=2) must now produce (2,2), because the second expression reads the candidate after the first assignment; the previous simultaneous result was (2,1). Keep the ordered assignment list and all preflight validation. Snapshot target indices from original rows before assigning (or retain the immutable original row source while constructing candidates, so membership is equivalent and independent). Change only the expression evaluation context from the old row to the candidate row and immediately store each result there. Do not write the original table as a shortcut. Check the complete final candidate table once in the existing order, then publish once; a late NULL/duplicate-key failure must discard all earlier candidates. Count matched rows even when their values do not change. Rubyのordered Array assignmentsとzip.eachの順は保存する。t.rows.dupに加えて対象row.dupを作りreplacement[j]だけを置換するので、元行配列には書かない。evaluateのrefはrow[e.index]を読むためここをreplacementへ渡す。元t.rows上のWHEREを保持し先に対象を確定する。raiseによりconstraints失敗ではt.rows=rowsと出力へ達しない。constraintsの対象each順、NULL列順、その後全rows.countのPK確認とrow_countを含む。

## Minimization and alternatives

The interaction scope requires the UPDATE validation/candidate/constraint/commit chain, not lexer, all SELECT operators, joins, rendering or every statement. Selected parser/list-order evidence where needed, the destination-name/duplicate helper, type/condition check boundaries, column-reference evaluation, candidate ownership, final constraint helper and count formatting. Expression checking and all other operator implementations remain unchanged; their complete bodies would add unrelated operations, while dropping the row-context read, independent candidate or commit guard would make the proposed semantics and rollback unprovable. Comparing a local candidate-row approach with in-place mutation plus rollback shows the former preserves atomicity with fewer changes. Reviewed the resulting excerpt independently; each retained complete source line supports a shared requirement and no program modification or execution is claimed.

The excerpt contains 1847 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
