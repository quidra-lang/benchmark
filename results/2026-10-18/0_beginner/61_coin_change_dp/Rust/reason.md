# Task B selection: 61_coin_change_dp / Rust

## Common answer requirements

Change only the ways recurrence to count ordered sequences by their last coin, preserving the amount-zero base and the other calculations.

## Source evidence

The existing coin-first traversal builds combinations one denomination at a time. Keep the one way for amount zero and zero for positive amounts before contributions. Traverse positive amounts in increasing order on the outside, and consider each coin on the inside if it fits. Add the already computed count at amount minus that coin: each sequence in that count extends uniquely with this last coin. Preserve minimum, greedy and output.

## Minimization

Only the ways storage, base and loop ordering/recurrence govern the modification. Target literals and unaffected algorithms do not add evidence.

Selected complete lines of `main.rs`: 4–5, 14–16. The prior excerpt measured 82 tokens; this excerpt measures 75 with `metric/tokenizer.py`.
