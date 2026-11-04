# Task B selection for 49_bracket_balance

Track the scan index with each opening bracket pushed and discard that index whenever a matching opening bracket is popped. On clean EOF with a nonempty stack, use its oldest remaining index instead of len(text). A mismatched closing bracket still stores its scan index and breaks immediately. The existing output uses the same failure variable, so formatting is outside the change.

Selected complete lines in order are 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 23, 24.

Task A uses 458 tokens. Task B uses 204 tokens.
