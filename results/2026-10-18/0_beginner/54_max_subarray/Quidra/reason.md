# Task B selection for 54_max_subarray

The selected second array and Kadane update show that a negative current total restarts the candidate at the new index. Before 10 the candidate has sum 1 and starts at index 1. The 10 extends it to 11 and sets the best range to [1,5]. The next -2 extends the candidate to sum 9 without changing that stored best range. The strict comparison and separate best_start and best_end assignments preserve the earlier range until a strictly better total appears.

Selected complete lines in order are 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21.

Task A uses 370 tokens. Task B uses 281 tokens.
