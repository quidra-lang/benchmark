# Task B selection: 96_poker_hand_rank / Quidra

The question requires both named hands' classification and tie comparison, the ace-low recognition and comparison-sequence exception, and preservation of the original strings in output. The selected two fixture rows supply exactly those hands; all eight remain in Task A. Rank mapping, counts, suit checks, present-rank/pattern construction and the higher category guards establish that both are nonflush straights and reach category 4. The first has present ranks [2,3,4,5,14], making wheel true even though max-min is not 4; the other has [2,3,4,5,6] and is an ordinary straight.

The normal descending count/rank sequence and the wheel override yield [5,4,3,2,1] versus [6,5,4,3,2]. Descending lexicographic score ordering therefore places the six-high straight first. The score return combines category and sequence, keys are computed without modifying hands, lex_order returns source indices, and printing indexes hands[best]. Internal comparison order never rewrites the original card string.

Known collections.index, lex_order, text.characters and native stable keyed-sort semantics suffice without their implementations. The layout variant preserves every non-whitespace token and only places one original hand per line. The selected lines retain the same algorithm and boundary evidence as the reviewed baseline. The original two packed fixture rows are a larger sufficient alternative because they carry six additional hands. Extra lower-category branches are never reached for either required trace.

Selected complete main.qui lines: 1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 35, 36, 37, 38, 40, 42, 45, 54, 55, 56, 57. Each is copied verbatim once and in source order.

Using unchanged metric/tokenizer.py: Task A **878** tokens; Task B **626** tokens. These are source-token measures. This is a minimized sufficient selection among the reviewed alternatives, not a proof of a global minimum. Native compiler/output checks are recorded separately in validation.json.
