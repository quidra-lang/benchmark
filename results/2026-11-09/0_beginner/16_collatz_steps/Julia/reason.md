# Task B: 16_collatz_steps / Julia

Change the single rendering expression to emit the original input, then `: max=`, the maximum value, ` steps=`, steps, and its newline. The result has one space before each field and no spaces around either equals sign. M comes from the existing maximum binding and K from the existing step-count binding; their calculations do not change.

The println expression supplies start, steps and peak as separate arguments without implicit separators; reorder the explicit fragments and operands.

Evidence is from `main.jl`, L8.

- L8: `println(start, ": steps=", steps, " max=", peak)`

Minimization: One complete output-format line contains every literal and value reference needed. The Collatz loop and maximum/step updates are outside this expression-only change. The selected complete original lines, in source order, cost 27 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 27, and the complete source costs 137. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
