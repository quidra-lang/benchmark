# Task B: 66_fisher_yates_shuffle / J

The descending shuffle loop includes i=1 and excludes i=0. At i=1 it first advances the MINSTD state, then computes j=state mod 2, so j is only 0 or 1. Swapping with itself when j=1 leaves ordering unchanged but still consumes this already generated random value. The iteration then ends and the descending range is exhausted.

The zero-based i labels select deck positions directly; both explicit element writes occur after the state and j calculations, including a self-swap.

Evidence is from `main.ijs`, L8,L9,L10,L11,L12,L13,L14,L15.

- L8: `for_i. |.>:i.51 do.`
- L9: `state =. 2147483647|48271*state`
- L10: `j =. (i+1)|state`
- L11: `left =. i{deck`
- L12: `right =. j{deck`
- L13: `deck =. right i}deck`
- L14: `deck =. left j}deck`
- L15: `end.`

Minimization: The descending range, state recurrence, modulo expression and swap form the entire final-iteration dependency. Deck initialization and previous shuffles are unnecessary. The selected complete original lines, in source order, cost 94 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 94, and the complete source costs 229. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
