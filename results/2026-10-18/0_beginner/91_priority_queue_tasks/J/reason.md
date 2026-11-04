# Task B selection — 91_priority_queue_tasks / J

The heap contains insertion IDs. The before verb currently compares the IDs for equal priorities; look up both IDs in the parallel names table and compare those names in ascending order. Expose the table to before because names is presently a main-local binding. The heap push and pop use the shared comparator, and both output paths use pop. The command fixtures and print formats add no additional ordering logic.

Selected complete source lines: 5, 6, 8, 13, 20, 30, 32, 47, 48, 50, 52, 53, 57.

With the benchmark tokenizer, this selection measures 233 tokens; the previous selection measured 203. The full source is 738 tokens.
