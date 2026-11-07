# Task B: 18_number_with_commas / Julia

The stored negative input makes the named sign decision true. Formatting uses abs(-456789)=456789, so grouping digits from the right creates 456,789 before the minus sign is reattached. The completed line is `-456,789`. The sign is outside the grouped magnitude; grouping inserts separators only between nonempty three-digit groups, so neither a comma after the sign nor a final comma occurs.

The regular expression finds positions with a digit on the left and a whole positive number of three-digit groups through the right end, then inserts commas. The sign conditional prefixes the result.

Evidence is from `main.jl`, L1,L2,L3,L4.

- L1: `for n in [0, 7, 999, 1000, -456789, 3141592, 9876543210]`
- L2: `negative = n < 0`
- L3: `magnitude = replace(string(abs(n)), r"(?<=\d)(?=(\d{3})+$)" => ",")`
- L4: `println(negative ? "-"*magnitude : magnitude)`

Minimization: The input binder, sign decision, magnitude formatting and output cover the complete requested path. Sign behavior cannot be inferred from magnitude formatting alone, so both stages are retained. The selected complete original lines, in source order, cost 129 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 129, and the complete source costs 131. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
