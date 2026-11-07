# Task B: 44_luhn_checksum / R

The original membership number stays a string, retaining its leading 0. Scanning from the right leaves the check digit 4 undoubled; every second digit from there is doubled and reduced by 9 if above 9. The transformed sum is 42, so it is invalid. Removing the current check digit gives 38, and the replacement is (-38) mod 10 =2. The completed line is `0128469655154: invalid (expected check digit 2)`.

The reversed digit vector has positions 1,3,... unchanged and even positions doubled/reduced; the original string remains the output argument.

Evidence is from `main.R`, L1,L2,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16.

- L1: `numbers <- c(`
- L2: `"688126340316", "0128469655154", "92181914514156", "177332430060552", "7982377590420309",`
- L4: `)`
- L5: `for (number in numbers) {`
- L6: `digits <- rev(utf8ToInt(number) - 48L)`
- L7: `even <- seq(2, length(digits), by = 2)`
- L8: `digits[even] <- 2L * digits[even]`
- L9: `digits[digits > 9] <- digits[digits > 9] - 9L`
- L10: `total <- sum(digits)`
- L11: `if (total %% 10 == 0) {`
- L12: `cat(sprintf("%s: valid\n", number))`
- L13: `} else {`
- L14: `expected <- (-(total - digits[1])) %% 10`
- L15: `cat(sprintf("%s: invalid (expected check digit %d)\n", number, expected))`
- L16: `}`

Minimization: The literal string and the entire local transform/check/output block establish leading-zero preservation, parity and exact line. Other number literals can be omitted when separately written. The selected complete original lines, in source order, cost 314 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 334, and the complete source costs 336. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
