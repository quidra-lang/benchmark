# Task B: 05_digit_sum_reverse / Julia

The input stays 98000 for the label. Its decimal digits are 9,8,0,0,0, so the digit count is 5 and the digit sum is 17; zeros remain elements and therefore count. Reversing the decimal digits gives textual 00089, whose numeric interpretation is 89. The completed line is `98000: digits=5 sum=17 reversed=89`.

digits(input) retains the five base-ten positions in least-significant-first order. Reversing string(input) and parse(Int,...) yields 89, while sum(decimal_digits) yields 17.

Evidence is from `main.jl`, L1,L2,L3,L4,L5,L6,L7.

- L1: `for original in [7, 98000, 4096, 50301, 2718281, 123456789]`
- L2: `decimal_digits = digits(original)`
- L3: `count = length(decimal_digits)`
- L4: `reversed = parse(Int, reverse(string(original)))`
- L5: `println(`
- L6: `"$original: digits=$(count) sum=$(sum(decimal_digits)) reversed=$reversed",`
- L7: `)`

Minimization: The chosen input binding, digit construction, named count, reverse conversion and complete output are all required for this end-to-end line. No unrelated input needs tracing. The selected complete original lines, in source order, cost 133 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 133, and the complete source costs 135. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
