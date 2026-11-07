# Task B: 54_max_subarray / Julia

The current source already supports nonempty all-negative arrays: current and best start at the first actual element, not zero. For [-6,-3,-9], -3 beats extending -6 to -9, so restart at the second element; extending it by -9 cannot beat best=-3. The resulting best nonempty range is zero-based [1,1], sum -3. No artificial empty zero-sum candidate exists and no initialization change is needed.

The source initializes from values[1] and translates its one-based position to zero-based reported bounds.

Evidence is from `main.jl`, L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20.

- L6: `for numbers in arrays`
- L7: `current = best = numbers[1]`
- L8: `start = best_start = best_end = 1`
- L9: `for i = 2:length(numbers)`
- L10: `if numbers[i] > current+numbers[i]`
- L11: `current = numbers[i]`
- L12: `start = i`
- L13: `else`
- L14: `current += numbers[i]`
- L15: `end`
- L16: `if current > best`
- L17: `best, best_start, best_end = current, start, i`
- L18: `end`
- L19: `end`
- L20: `println("max sum ", best, " at [", best_start-1, ", ", best_end-1, "]")`

Minimization: First-element initialization, restart/extension recurrence and best-range/output update establish the requested extension. The original three unrelated array literals are not needed to analyze the proposed new input. The selected complete original lines, in source order, cost 203 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 203, and the complete source costs 368. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
