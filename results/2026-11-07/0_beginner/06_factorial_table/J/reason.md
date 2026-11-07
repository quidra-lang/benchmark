# Task B: 06_factorial_table / J

Rename the loop binding for the current term to term_number, and follow that rename in its factorial operand/table index and numeric n! label operand. The literal `! = ` stays unchanged. A built-in factorial name, the independent precomputed factorial table, and any separately scoped callable parameter are different bindings and keep their names.

The for_n. binder and both n references in smoutput/factorial must agree.

Evidence is from `main.ijs`, L2,L3.

- L2: `for_n. i.13 do.`
- L3: `smoutput (":n), '! = ', (, '0' 8!:2 !n)`

Minimization: The binder and its output/calculation references supply this local rename analysis. R also needs the table definition to distinguish factorials from the renamed current-term binding; no other factorial terms require evaluation. The selected complete original lines, in source order, cost 45 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 45, and the complete source costs 65. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
