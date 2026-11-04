# Task B selection — 95_huffman_coding / Rust

## Common answer requirements

Reverse the bit labels for left and right recursion while preserving child selection, symbol order, and both bit totals.

## Source evidence

The first assign call selects the left child and adds 0 to the path. The second selects the right child and adds 1. Exchange just these two bit literals. Every code is complemented with unchanged length, so the length-based bit totals and symbol ordering are unaffected.

## Minimization

Selected complete lines of `main.rs`: L27, L29, L30, L33. The first call spans several source lines. The retained call head, child and path establish the left move and label. The separate arguments for the node store and code output, and the call terminator, add no fact about the bit assignment.

The selected excerpt measures **62 tokens** with `metric/tokenizer.py`.
