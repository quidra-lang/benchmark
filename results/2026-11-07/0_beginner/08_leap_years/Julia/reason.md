# Task B: 08_leap_years / Julia

Append 2400 after 2100 in the existing input collection. The same per-year test classifies it as a leap year: divisibility by 4 is true and the century exception is overridden by divisibility by 400. Sequential iteration appends exactly the ninth line, `2400: leap year`; previous elements keep their order and use the same independent test.

The for input array preserves order; the short-circuit Gregorian Boolean supplies the lowercase ternary label to println.

Evidence is from `main.jl`, L1,L2,L3.

- L1: `for year in [1900, 1988, 2000, 2019, 2024, 2026, 2032, 2100]`
- L2: `leap = year % 400 == 0 || (year % 4 == 0 && year % 100 != 0)`
- L3: `println(year, ": ", leap ? "leap year" : "common year")`

Minimization: The collection, test, label choice and output are the complete path requested. There is no state shared across years that would require any other source. The selected complete original lines, in source order, cost 131 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 131, and the complete source costs 133. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
