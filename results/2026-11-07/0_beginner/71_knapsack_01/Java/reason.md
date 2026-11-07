# Task B selection: 71_knapsack_01 / Java

Zero-filled DP gives zero-item/zero-capacity base states. At the first tent decision, capacity below 10 retains zero and capacity at least 10 compares zero with 120 from the previous item stage. Every include/exclude transition reads row i-1, preventing repeated use of one item. Backward differing-state checks mark chosen items and reduce capacity; final filtering reads marks in original name order.

Keep item data, DP initialization/transitions, reconstruction start/read/update and original-order name emission. Max-value and total-weight reporting do not establish these stage dependencies.

Selected complete source lines in `Main.java`: 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 28. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
