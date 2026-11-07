# Task B selection: 96_poker_hand_rank / Kotlin

Index in 23456789TJQKA plus two encodes T as 10 and A as 14. Sorted distinct ranks [2,3,4,5,14] identify the wheel; its comparison sequence is explicitly [5,4,3,2,1], unlike the ordinary ace-high descending sequence beginning 14. Those rank values are distinct from the later printed one-based hand position.

Only rank encoding, wheel/straight test and comparison sequence construction are needed. Hand-category selection, input hands, sorting and printed positions do not determine this local rank representation.

Selected complete source lines in `main.kt`: 5, 6, 7, 8, 23, 24. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
