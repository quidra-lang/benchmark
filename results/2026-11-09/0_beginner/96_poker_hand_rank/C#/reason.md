# Task B selection: 96_poker_hand_rank / C#

Index in 23456789TJQKA plus two encodes T as 10 and A as 14. Sorted distinct ranks [2,3,4,5,14] identify the wheel; its comparison sequence is explicitly [5,4,3,2,1], unlike the ordinary ace-high descending sequence beginning 14. Those rank values are distinct from the later printed one-based hand position.

Only rank encoding, wheel/straight test and comparison sequence construction are needed. Hand-category selection, input hands, sorting and printed positions do not determine this local rank representation.

Selected complete source lines in `Program.cs`: 10, 11, 12, 13, 14, 27, 28. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
