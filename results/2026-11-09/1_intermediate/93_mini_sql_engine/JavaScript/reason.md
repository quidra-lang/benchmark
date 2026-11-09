# Task B selection — JavaScript

## Answer requirements shared across languages

1. Locate the ordered UPDATE assignment representation, preserve table lookup, left-to-right target-column lookup and duplicate rejection, then each expression check and its destination-type check, then WHERE validation.
2. Freeze target membership from original table rows and their original values; evaluate each selected row into a separate candidate row from left to right, making later expressions read the already-updated candidate.
3. Keep final constraints in target row order, NOT NULL by column order before primary-key uniqueness against the entire final candidate table, and publish only after every constraint succeeds.
4. Preserve the original table on any failure and retain the number of target rows including unchanged rows, with the singular/plural rows-updated output; explain the ownership/copy boundary using source and language semantics.

## Selected source locations

- `main.js`: 38, 39, 40, 41, 49, 50, 51, 162, 163, 164, 165, 166, 372, 373, 374, 375, 376, 377, 378, 379, 380, 381, 399, 400, 401, 402, 403, 404, 405, 406, 407, 408, 409, 410, 411, 412, 413, 414, 415, 416, 417, 418, 419, 420, 421, 422, 423, 424, 425, 426, 451, 452, 453, 487, 488, 489, 546, 547, 548, 549, 550, 551, 552, 553, 554, 555, 556, 557, 558, 559, 560, 561, 562, 563, 564, 565, 566, 567, 568, 569, 570, 571, 572, 723, 728, 729, 755, 756, 757, 758, 759, 760, 761, 762, 763, 764, 765, 766, 767, 768, 769, 770, 771, 772, 773, 774, 775, 776, 777, 785, 786, 787, 788, 789, 790

## Evidence and language semantics

SET a=b, b=a on a row (a=1,b=2) must now produce (2,2), because the second expression reads the candidate after the first assignment; the previous simultaneous result was (2,1). Keep the ordered assignment list and all preflight validation. Snapshot target indices from original rows before assigning (or retain the immutable original row source while constructing candidates, so membership is equivalent and independent). Change only the expression evaluation context from the old row to the candidate row and immediately store each result there. Do not write the original table as a shortcut. Check the complete final candidate table once in the existing order, then publish once; a late NULL/duplicate-key failure must discard all earlier candidates. Count matched rows even when their values do not change. JavaScriptはordered assignmentsをArray.map/forEachで検証する。現状valuesを旧rowから全件先計算するため、values一括生成と後置forEachを候補resultへ逐次評価代入する一つの順序ループへ変える必要がある。result=[...row]が行容器を分離し、元table.rows.mapの引数rowは旧値のまま。changedの長さと最終table.rows=rowsが制約後なので、throwでは全表が保存される。PK比較は未対象も含むrows.some。

## Minimization and alternatives

The interaction scope requires the UPDATE validation/candidate/constraint/commit chain, not lexer, all SELECT operators, joins, rendering or every statement. Selected parser/list-order evidence where needed, the destination-name/duplicate helper, type/condition check boundaries, column-reference evaluation, candidate ownership, final constraint helper and count formatting. Expression checking and all other operator implementations remain unchanged; their complete bodies would add unrelated operations, while dropping the row-context read, independent candidate or commit guard would make the proposed semantics and rollback unprovable. Comparing a local candidate-row approach with in-place mutation plus rollback shows the former preserves atomicity with fewer changes. Reviewed the resulting excerpt independently; each retained complete source line supports a shared requirement and no program modification or execution is claimed.

The excerpt contains 2201 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
