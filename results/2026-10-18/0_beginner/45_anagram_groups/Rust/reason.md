# Task B selection: 45_anagram_groups / Rust

Locate the group membership and output boundary; explain how to omit singletons while keeping the key rule, word order and first-appearance order.

Keep building groups from all twelve words using the existing signature. For code with materialized groups, test the finished group size immediately before its output and suppress the whole line when the size is one. For code that streams words directly, count matches with the same signature test before any write, or accumulate the matched words first. Preserve the existing first-unused/index or insertion-order traversal and the original append order. Do not print a blank line for a singleton.

The loop over completed groups supplies the insertion site for the check without tracing the original grouping procedure. For immediate writes, the existing equality test and newline are both needed: suppressing the printed words alone could still emit a placeholder.

The group vector is already available after scanning matches for the first unused index; put the test after that scan, retaining used-marking.

Source: `main.rs`, original lines 17–24. The previous excerpt measures 23 tokens; this evidence set measures 127 tokens.
