# Task B: 06_factorial_table / R

Rename the loop binding for the current term to term_number, and follow that rename in its factorial operand/table index and numeric n! label operand. The literal `! = ` stays unchanged. A built-in factorial name, the independent precomputed factorial table, and any separately scoped callable parameter are different bindings and keep their names.

The for(n in 0:12) binder and n references in the label and factorials[n+1] follow the rename; factorials is a different binding.

Evidence is from `main.R`, L1,L2,L3.

- L1: `factorials <- cumprod(c(1, 1:12))`
- L2: `for (n in 0:12) {`
- L3: `cat(sprintf("%d! = %d\n", n, factorials[n + 1]))`

Minimization: The binder and its output/calculation references supply this local rename analysis. R also needs the table definition to distinguish factorials from the renamed current-term binding; no other factorial terms require evaluation. The selected complete original lines, in source order, cost 66 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 66, and the complete source costs 68. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
