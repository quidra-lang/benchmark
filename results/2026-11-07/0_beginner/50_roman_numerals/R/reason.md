# Task B: 50_roman_numerals / R

Encoding 1994 greedily appends M,CM,XC,IV as remaining becomes 994,94,4,0, producing MCMXCIV. The decoder receives that generated string. It maps symbols to 1000,100,1000,10,100,1,5 and subtracts a value only when followed by a greater one: 1000-100+1000-10+100-1+5=1994. Thus the numeric-to-Roman operation and Roman-to-numeric operation are separate stages joined by the encoded string.

The encoder returns its accumulated string; from_roman receives roman and compares consecutive mapped symbol values.

Evidence is from `main.R`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L14,L15,L16,L17,L18,L19,L20,L21,L22,L25,L26.

- L1: `to_roman <- function(number) {`
- L2: `values <- c(1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1)`
- L3: `symbols <- c("M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I")`
- L4: `result <- ""`
- L5: `for (i in seq_along(values)) {`
- L6: `while (number >= values[i]) {`
- L7: `result <- paste0(result, symbols[i])`
- L8: `number <- number - values[i]`
- L9: `}`
- L10: `}`
- L11: `result`
- L12: `}`
- L14: `from_roman <- function(roman) {`
- L15: `table <- c(I = 1, V = 5, X = 10, L = 50, C = 100, D = 500, M = 1000)`
- L16: `values <- unname(table[strsplit(roman, "", fixed = TRUE)[[1]]])`
- L17: `total <- 0`
- L18: `for (i in seq_along(values)) {`
- L19: `total <- total + if (i < length(values) && values[i] < values[i + 1]) -values[i] else values[i]`
- L20: `}`
- L21: `total`
- L22: `}`
- L25: `roman <- to_roman(number)`
- L26: `cat(sprintf("%d -> %s -> %d\n", number, roman, from_roman(roman)))`

Minimization: The conversion tables, complete encoder/decoder algorithms and the call boundary are needed to trace this subtractive case. Unrelated input literals/output labels are omitted where independent lines allow it. The selected complete original lines, in source order, cost 475 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 527, and the complete source costs 529. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
