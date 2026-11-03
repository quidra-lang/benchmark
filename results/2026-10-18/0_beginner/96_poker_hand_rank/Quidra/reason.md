# Task B selection for 96_poker_hand_rank

The selected fixture rows, rank counts and suit checks identify both hands as nonflush straights. The wheel check accepts the ace-low ranks and substitutes [5,4,3,2,1] for comparison; the six-high hand retains [6,5,4,3,2]. Descending lexicographic order puts the six-high hand first. The output indexes the original hands using the sorted indices and preserves each hand string.

Selected complete lines in order are 1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 35, 36, 37, 38, 40, 42, 45, 54, 55, 56, 57.

Task A uses 875 tokens. Task B uses 623 tokens.
