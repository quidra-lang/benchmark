# Task B selection for 48_josephus_problem

For n=7 and k=3, the addition of k minus one advances two positions. The initial range is 1 through 7, so indices 2, 4, and 1 remove 3, 6, and 2. remove_at returns the removed value and shifts subsequent entries left, so the retained index denotes the next person before adding the stride. The modulo uses the current length and wraps from the highest remaining number to the lowest. Display code is outside this trace.

Selected complete lines in order are 1, 5, 6, 9, 10, 11.

Task A uses 186 tokens. Task B uses 75 tokens.
