# Task B: 60_shopping_receipt / Julia

Food subtotals are milk 396, bread 248, apple 512 and eggs 268, totaling 1424. Truncating 1424×8/100 gives food tax 113. Per-item truncation would give 31+19+40+21=111, two less, so truncation belongs after category aggregation. General subtotal is 495+437=932, tax 93; payment adds untaxed subtotals once plus the two taxes: 1424+932+113+93=2562.

totals[category] accumulates price*quantity, then div(total*rate,100) truncates each category tax. payment += total+tax runs once per category.

Evidence is from `main.jl`, L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L15,L16,L17,L18,L19,L21,L22.

- L2: `items = [`
- L3: `("milk", 198, 2, "food"),`
- L4: `("notebook", 165, 3, "general"),`
- L5: `("bread", 248, 1, "food"),`
- L6: `("apple", 128, 4, "food"),`
- L7: `("detergent", 437, 1, "general"),`
- L8: `("eggs", 268, 1, "food"),`
- L9: `]`
- L10: `totals = Dict("food"=>0, "general"=>0)`
- L11: `for (name, price, quantity, category) in items`
- L12: `subtotal = price*quantity`
- L13: `totals[category] += subtotal`
- L15: `end`
- L16: `payment = 0`
- L17: `for (category, rate) in [("food", 8), ("general", 10)]`
- L18: `tax = div(totals[category]*rate, 100)`
- L19: `payment += totals[category]+tax`
- L21: `end`
- L22: `println("total: ", payment, " yen")`

Minimization: Item price/quantity/category data, subtotal aggregation, tax truncation and final addition are necessary for the requested numerical comparison. Per-item receipt formatting is omitted when separately written. The selected complete original lines, in source order, cost 304 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 377, and the complete source costs 388. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
