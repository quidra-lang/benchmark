# Task B selection: 66_fisher_yates_shuffle / Kotlin

The final i=1 iteration first advances MINSTD state, then takes its nonnegative remainder modulo i+1=2, giving j in {0,1}, and performs a swap. A self-swap still follows the state update and consumes that value. The descending loop stops at 1, so no i=0 iteration occurs.

Only the loop header and one full update/index/swap body are needed. Seed, deck construction and final printing do not determine final-iteration boundaries or update order.

Selected complete source lines in `main.kt`: 4, 5, 6, 7, 8, 9, 10. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
