# Task B selection: 98_bank_queue_simulation / C#

Rename state at its seed declaration, both recurrence assignments (including right-side reads) and both random-value reads to rng_state. arrival is separately initialized accumulated time; its += consumes a derived random increment and must keep its independent binding. Customer assignment/free times are unrelated to this name change.

Keep only both state updates/reads plus distinct arrival introduction. Teller scheduling and all output/calculation details beyond these reads add no binding evidence.

Selected complete source lines in `Program.cs`: 6, 8, 11, 12, 13, 14. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
