# Task B: 60_shopping_receipt / R

Food subtotals are milk 396, bread 248, apple 512 and eggs 268, totaling 1424. Truncating 1424×8/100 gives food tax 113. Per-item truncation would give 31+19+40+21=111, two less, so truncation belongs after category aggregation. General subtotal is 495+437=932, tax 93; payment adds untaxed subtotals once plus the two taxes: 1424+932+113+93=2562.

tapply(subtotal,category,sum) aggregates first; %/% 100L truncates each positive category-rate product, and the final sum adds subtotals plus taxes.

Evidence is from `main.R`, L1,L2,L3,L4,L5,L6,L8,L9,L10,L12.

- L1: `items <- data.frame(`
- L2: `name = c("milk", "notebook", "bread", "apple", "detergent", "eggs"),`
- L3: `price = c(198L, 165L, 248L, 128L, 437L, 268L), quantity = c(2L, 3L, 1L, 4L, 1L, 1L),`
- L4: `category = c("food", "general", "food", "food", "general", "food")`
- L5: `)`
- L6: `subtotals <- items$price * items$quantity`
- L8: `categories <- c("food", "general")`
- L9: `totals <- tapply(subtotals, items$category, sum)[categories]`
- L10: `taxes <- (totals * c(8L, 10L)) %/% 100L`
- L12: `cat(sprintf("total: %d yen\n", sum(totals) + sum(taxes)))`

Minimization: Item price/quantity/category data, subtotal aggregation, tax truncation and final addition are necessary for the requested numerical comparison. Per-item receipt formatting is omitted when separately written. The selected complete original lines, in source order, cost 270 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 365, and the complete source costs 365. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
