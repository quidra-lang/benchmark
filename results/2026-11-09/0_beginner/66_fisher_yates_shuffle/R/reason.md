# Task B: 66_fisher_yates_shuffle / R

The descending shuffle loop includes i=1 and excludes i=0. At i=1 it first advances the MINSTD state, then computes j=state mod 2, so j is only 0 or 1. Swapping with itself when j=1 leaves ordering unchanged but still consumes this already generated random value. The iteration then ends and the descending range is exhausted.

The logical range ends at 1; j is translated to one-based vector positions and the swap occurs after the state update.

Evidence is from `main.R`, L4,L5,L6,L7,L8.

- L4: `for (i in 51:1) {`
- L5: `state <- (state * 48271) %% 2147483647`
- L6: `j <- state %% (i + 1)`
- L7: `deck[c(i + 1, j + 1)] <- deck[c(j + 1, i + 1)]`
- L8: `}`

Minimization: The descending range, state recurrence, modulo expression and swap form the entire final-iteration dependency. Deck initialization and previous shuffles are unnecessary. The selected complete original lines, in source order, cost 105 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 105, and the complete source costs 263. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
