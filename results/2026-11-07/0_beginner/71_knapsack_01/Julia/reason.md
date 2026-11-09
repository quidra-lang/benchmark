# Task B: 71_knapsack_01 / Julia

Zero-initialized DP represents zero items and zero capacity. For the first tent (weight 10,value 120), capacities below 10 keep zero and capacities at least 10 compare zero against 120 plus the preceding-item zero state. Every later take/skip reads only the preceding item stage, preventing reuse of the same item. Traceback compares current with preceding-stage values, marks a differing item and subtracts its weight; the selected mask/names are finally read in original item order.

The DP has an extra zero-item row and zero-capacity column; table[i,...] is the preceding stage for table[i+1,...]. Reverse traceback marks chosen then names use its original-order mask.

Evidence is from `main.jl`, L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L31.

- L2: `items = [`
- L3: `("tent", 10, 120),`
- L4: `("stove", 3, 65),`
- L5: `("lantern", 2, 45),`
- L6: `("rope", 3, 20),`
- L7: `("camera", 5, 90),`
- L8: `("blanket", 5, 85),`
- L9: `("water", 6, 100),`
- L10: `]`
- L11: `capacity = 20`
- L12: `table = zeros(Int, length(items)+1, capacity+1)`
- L13: `for i in eachindex(items), weight = 0:capacity`
- L14: `item_weight, item_value = items[i][2], items[i][3]`
- L15: `table[i+1, weight+1] = table[i, weight+1]`
- L16: `if item_weight <= weight`
- L17: `table[i+1, weight+1] =`
- L18: `max(table[i+1, weight+1], table[i, weight-item_weight+1]+item_value)`
- L19: `end`
- L20: `end`
- L21: `chosen = falses(length(items))`
- L22: `remaining = capacity`
- L23: `for i = length(items):-1:1`
- L24: `if table[i+1, remaining+1] != table[i, remaining+1]`
- L25: `chosen[i] = true`
- L26: `remaining -= items[i][2]`
- L27: `end`
- L28: `end`
- L31: `println("items: ", join((items[i][1] for i in eachindex(items) if chosen[i]), " "))`

Minimization: Item identity/weight/value data, zero base, preceding-stage transition and traceback/name selection all belong to the requested stage chain. Final value/weight summary formatting is unnecessary where separately written. The selected complete original lines, in source order, cost 453 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 491, and the complete source costs 502. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
