# Task B selection — TypeScript

## Answer requirements shared across languages

1. Locate the ordered UPDATE assignment representation, preserve table lookup, left-to-right target-column lookup and duplicate rejection, then each expression check and its destination-type check, then WHERE validation.
2. Freeze target membership from original table rows and their original values; evaluate each selected row into a separate candidate row from left to right, making later expressions read the already-updated candidate.
3. Keep final constraints in target row order, NOT NULL by column order before primary-key uniqueness against the entire final candidate table, and publish only after every constraint succeeds.
4. Preserve the original table on any failure and retain the number of target rows including unchanged rows, with the singular/plural rows-updated output; explain the ownership/copy boundary using source and language semantics.

## Selected source locations

- `main.ts`: 3, 4, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 86, 87, 88, 89, 97, 98, 99, 211, 212, 213, 214, 215, 421, 422, 423, 424, 425, 426, 427, 428, 429, 430, 448, 449, 450, 451, 452, 453, 454, 455, 456, 457, 458, 459, 460, 461, 462, 463, 464, 465, 466, 467, 468, 469, 470, 471, 472, 473, 474, 475, 476, 477, 478, 479, 480, 481, 506, 507, 508, 509, 510, 511, 512, 513, 514, 550, 551, 552, 610, 611, 612, 613, 614, 615, 616, 617, 618, 619, 620, 621, 622, 623, 624, 625, 626, 627, 628, 629, 630, 631, 632, 633, 634, 635, 636, 787, 792, 793, 819, 820, 821, 822, 823, 824, 825, 826, 827, 828, 829, 830, 831, 832, 833, 834, 835, 836, 837, 838, 839, 840, 841, 849, 850, 851, 852, 853, 854

## Evidence and language semantics

SET a=b, b=a on a row (a=1,b=2) must now produce (2,2), because the second expression reads the candidate after the first assignment; the previous simultaneous result was (2,1). Keep the ordered assignment list and all preflight validation. Snapshot target indices from original rows before assigning (or retain the immutable original row source while constructing candidates, so membership is equivalent and independent). Change only the expression evaluation context from the old row to the candidate row and immediately store each result there. Do not write the original table as a shortcut. Check the complete final candidate table once in the existing order, then publish once; a late NULL/duplicate-key failure must discard all earlier candidates. Count matched rows even when their values do not change. TypeScriptのValueはnumber|string|null、rowsはValue[][]。spreadは行Arrayを独立させ、値は不変プリミティブであり深い複製は不要。現状のvalues=assignments.mapは旧rowの全式評価なので、その一括計算を候補resultに対する逐次評価代入へ置き換える。table.rows本体は制約成功後の一回だけ代入され、throwで中止できる。型チェック各式直後、WHERE後置、NULL→全候補PK→件数出力の順を保持する。

## Minimization and alternatives

The interaction scope requires the UPDATE validation/candidate/constraint/commit chain, not lexer, all SELECT operators, joins, rendering or every statement. Selected parser/list-order evidence where needed, the destination-name/duplicate helper, type/condition check boundaries, column-reference evaluation, candidate ownership, final constraint helper and count formatting. Expression checking and all other operator implementations remain unchanged; their complete bodies would add unrelated operations, while dropping the row-context read, independent candidate or commit guard would make the proposed semantics and rollback unprovable. Comparing a local candidate-row approach with in-place mutation plus rollback shows the former preserves atomicity with fewer changes. Reviewed the resulting excerpt independently; each retained complete source line supports a shared requirement and no program modification or execution is claimed.

The excerpt contains 2504 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
