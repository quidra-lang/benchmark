# Task B: 08_leap_years / R

Append 2400 after 2100 in the existing input collection. The same per-year test classifies it as a leap year: divisibility by 4 is true and the century exception is overridden by divisibility by 400. Sequential iteration appends exactly the ninth line, `2400: leap year`; previous elements keep their order and use the same independent test.

The for input vector preserves order; the Gregorian predicate supplies the lowercase ifelse label to cat/sprintf.

Evidence is from `main.R`, L1,L2,L3.

- L1: `for (year in c(1900, 1988, 2000, 2019, 2024, 2026, 2032, 2100)) {`
- L2: `leap <- year %% 400 == 0 || (year %% 4 == 0 && year %% 100 != 0)`
- L3: `cat(sprintf("%04d: %s\n", year, if (leap) "leap year" else "common year"))`

Minimization: The collection, test, label choice and output are the complete path requested. There is no state shared across years that would require any other source. The selected complete original lines, in source order, cost 148 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 148, and the complete source costs 150. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
