# Task B: 06_factorial_table / Julia

Rename the loop binding for the current term to term_number, and follow that rename in its factorial operand/table index and numeric n! label operand. The literal `! = ` stays unchanged. A built-in factorial name, the independent precomputed factorial table, and any separately scoped callable parameter are different bindings and keep their names.

The for n binder, the first println argument and factorial(n) refer to that same local n.

Evidence is from `main.jl`, L1,L2.

- L1: `for n = 0:12`
- L2: `println(n, "! = ", factorial(n))`

Minimization: The binder and its output/calculation references supply this local rename analysis. R also needs the table definition to distinguish factorials from the renamed current-term binding; no other factorial terms require evaluation. The selected complete original lines, in source order, cost 31 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 31, and the complete source costs 33. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
