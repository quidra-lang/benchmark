# Task B selection — Python

## Answer requirements shared across languages

1. Locate the ordered UPDATE assignment representation, preserve table lookup, left-to-right target-column lookup and duplicate rejection, then each expression check and its destination-type check, then WHERE validation.
2. Freeze target membership from original table rows and their original values; evaluate each selected row into a separate candidate row from left to right, making later expressions read the already-updated candidate.
3. Keep final constraints in target row order, NOT NULL by column order before primary-key uniqueness against the entire final candidate table, and publish only after every constraint succeeds.
4. Preserve the original table on any failure and retain the number of target rows including unchanged rows, with the singular/plural rows-updated output; explain the ownership/copy boundary using source and language semantics.

## Selected source locations

- `main.py`: 27, 28, 264, 265, 266, 267, 268, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 503, 504, 505, 506, 507, 508, 509, 510, 511, 512, 513, 514, 515, 516, 517, 518, 519, 520, 521, 524, 525, 526, 527, 528, 529, 530, 531, 532, 533, 534, 535, 536, 537, 538, 539, 540, 541, 542, 543, 544, 545, 546, 547, 548, 549, 550, 551, 552, 553, 554, 555, 556, 557, 558, 559, 562, 563, 564, 565, 566, 567, 568, 569, 570, 571, 572, 573, 574, 575, 576, 577, 578, 579, 580, 581, 584, 585, 586, 587, 588, 589, 590, 591, 592, 593, 594, 595, 596, 597, 633, 634, 635, 644, 645, 646, 683, 684, 761, 762, 763, 764, 765, 766, 826, 827, 872, 873, 874, 875, 876, 877, 896, 897, 898, 899, 900, 901, 902, 903, 904, 905, 906, 907, 908, 909, 910, 911, 912, 913, 914, 915, 916, 917, 924, 925, 926, 927, 989, 990, 991, 992, 993, 994, 995, 996, 997, 998, 999, 1000, 1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008

## Evidence and language semantics

SET a=b, b=a on a row (a=1,b=2) must now produce (2,2), because the second expression reads the candidate after the first assignment; the previous simultaneous result was (2,1). Keep the ordered assignment list and all preflight validation. Snapshot target indices from original rows before assigning (or retain the immutable original row source while constructing candidates, so membership is equivalent and independent). Change only the expression evaluation context from the old row to the candidate row and immediately store each result there. Do not write the original table as a shortcut. Check the complete final candidate table once in the existing order, then publish once; a late NULL/duplicate-key failure must discard all earlier candidates. Count matched rows even when their values do not change. Pythonではlist(table.rows)だけでは各行を共有するが、対象行ごとにlist(row)を作ってその添字を置換しており元行へ書かない。evaluateのColumnRefは渡されたrow[expr.index]を読むのでnew_rowを評価文脈に選ぶ。現在のsatisfiesは未変更table.rowsのrowを読む。column_indicesは未知名を重複より先に検査、check/requireは各式順、WHEREはその後。constraintsは全候補のCounterを作り対象順のNULL検査後PKを判定。例外は最後のtable.rows代入を飛ばす。

## Minimization and alternatives

The interaction scope requires the UPDATE validation/candidate/constraint/commit chain, not lexer, all SELECT operators, joins, rendering or every statement. Selected parser/list-order evidence where needed, the destination-name/duplicate helper, type/condition check boundaries, column-reference evaluation, candidate ownership, final constraint helper and count formatting. Expression checking and all other operator implementations remain unchanged; their complete bodies would add unrelated operations, while dropping the row-context read, independent candidate or commit guard would make the proposed semantics and rollback unprovable. Comparing a local candidate-row approach with in-place mutation plus rollback shows the former preserves atomicity with fewer changes. Reviewed the resulting excerpt independently; each retained complete source line supports a shared requirement and no program modification or execution is claimed.

The excerpt contains 2223 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
