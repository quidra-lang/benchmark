# Task B: 71_knapsack_01 / R

Zero-initialized DP represents zero items and zero capacity. For the first tent (weight 10,value 120), capacities below 10 keep zero and capacities at least 10 compare zero against 120 plus the preceding-item zero state. Every later take/skip reads only the preceding item stage, preventing reuse of the same item. Traceback compares current with preceding-stage values, marks a differing item and subtracts its weight; the selected mask/names are finally read in original item order.

The extra base row/column store zeros. Each stage reads the previous row; reverse traceback stores a Boolean chosen vector and names[chosen] retains input order.

Evidence is from `main.R`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L23,L24,L25.

- L1: `names <- c("tent", "stove", "lantern", "rope", "camera", "blanket", "water")`
- L2: `weights <- c(10, 3, 2, 3, 5, 5, 6)`
- L3: `values <- c(120, 65, 45, 20, 90, 85, 100)`
- L4: `capacity <- 20`
- L5: `table <- matrix(0, length(names) + 1, capacity + 1)`
- L6: `for (i in seq_along(names)) {`
- L7: `for (weight in 0:capacity) {`
- L8: `table[i + 1, weight + 1] <- table[i, weight + 1]`
- L9: `if (weights[i] <= weight) {`
- L10: `table[i + 1, weight + 1] <- max(table[i + 1, weight + 1], table[i, weight - weights[i] + 1] + values[i])`
- L11: `}`
- L12: `}`
- L13: `}`
- L14: `chosen <- rep(FALSE, length(names))`
- L15: `remaining <- capacity`
- L16: `for (i in rev(seq_along(names))) {`
- L17: `if (table[i + 1, remaining + 1] != table[i, remaining + 1]) {`
- L18: `chosen[i] <- TRUE`
- L19: `remaining <- remaining - weights[i]`
- L20: `}`
- L21: `}`
- L23: `"max value: %d\ntotal weight: %d\nitems: %s\n",`
- L24: `table[nrow(table), ncol(table)], capacity - remaining, paste(names[chosen], collapse = " ")`
- L25: `))`

Minimization: Item identity/weight/value data, zero base, preceding-stage transition and traceback/name selection all belong to the requested stage chain. Final value/weight summary formatting is unnecessary where separately written. The selected complete original lines, in source order, cost 469 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 474, and the complete source costs 474. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
