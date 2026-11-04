# Task B selection: 78_bank_account / Rust

## Common answer requirements

Trace the two transfers and next withdrawal, including the equality boundary and why failure does not write either balance.

## Supported analysis

Emma starts at 800 and receives 1200; Nina starts at 12000 and sends 5000 to Leo. The transfers therefore start at Emma 2000 and Nina 7000. The 2500 transfer fails, with both debit and credit skipped. The 2000 transfer passes the inclusive check (or fails the strict insufficient-funds condition), leaving Emma at 0 and Nina at 9000. The next withdrawal of 300 fails against Emma’s new balance.

The excerpt is copied verbatim from `main.rs`, in source order. Retained source lines: 2, 3, 4, 5, 7, 9, 10, 11, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33. Additional evidence is on line 15: `]`; line 18: `{`.

## Minimization and alternatives

The prior transactions that alter either balance, the target transactions, parsing and account lookup determine the trace. Leo-only withdrawals have no effect when they can be omitted as whole lines, and later commands are outside the trace. The prior selection used 445 tokens; this selection uses 423 tokens. Task A is assumed to satisfy its requirements for this analysis, as specified in README §2.3.
