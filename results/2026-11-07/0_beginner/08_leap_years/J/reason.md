# Task B: 08_leap_years / J

Append 2400 after 2100 in the existing input collection. The same per-year test classifies it as a leap year: divisibility by 4 is true and the century exception is overridden by divisibility by 400. Sequential iteration appends exactly the ninth line, `2400: leap year`; previous elements keep their order and use the same independent test.

The loop reads the input vector in order, sets the default lowercase label, then replaces it only when the Boolean leap predicate is true.

Evidence is from `main.ijs`, L2,L3,L4,L5,L6,L7,L8.

- L2: `for_year. 1900 1988 2000 2019 2024 2026 2032 2100 do.`
- L3: `leap =. (0 = 400 | year) +. (0 = 4 | year) *. 0 ~: 100 | year`
- L4: `result =. 'common year'`
- L5: `if. leap do.`
- L6: `result =. 'leap year'`
- L7: `end.`
- L8: `smoutput (":year), ': ', result`

Minimization: The collection, test, label choice and output are the complete path requested. There is no state shared across years that would require any other source. The selected complete original lines, in source order, cost 146 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 146, and the complete source costs 166. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
