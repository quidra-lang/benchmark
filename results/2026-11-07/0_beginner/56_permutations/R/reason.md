# Task B: 56_permutations / R

Start with an empty prefix, no used characters and sequence number zero. At each depth try unused ABCD positions in order, so the first completion is `1: ABCD`. Recursion exhausts choices below A, ending that group with ADCB; restoring those choices permits B as the next first character and BACD as its first completion. Every leaf has four distinct characters; the 4×3×2×1 branches yield 24 lines, ending `24: DCBA`.

Each branch copies used into next_used before marking a choice, so caller state is preserved without an explicit undo; count is threaded through return values.

Evidence is from `main.R`, L1,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L19.

- L1: `characters <- strsplit("ABCD", "", fixed = TRUE)[[1]]`
- L3: `visit <- function(prefix, used, counter) {`
- L4: `if (nchar(prefix) == 4) {`
- L5: `counter <- counter + 1`
- L6: `cat(sprintf("%d: %s\n", counter, prefix))`
- L7: `return(counter)`
- L8: `}`
- L9: `for (i in seq_along(characters)) {`
- L10: `if (!used[i]) {`
- L11: `next_used <- used`
- L12: `next_used[i] <- TRUE`
- L13: `counter <- visit(paste0(prefix, characters[i]), next_used, counter)`
- L14: `}`
- L15: `}`
- L16: `counter`
- L17: `}`
- L19: `invisible(visit("", rep(FALSE, 4), 0))`

Minimization: The entry state and full small recursive enumerator are necessary to establish numbering, choice/restoration and exhaustiveness. No unrelated program logic or fallback selection is present. The selected complete original lines, in source order, cost 215 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 217, and the complete source costs 217. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
