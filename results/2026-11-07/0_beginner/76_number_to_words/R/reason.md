# Task B: 76_number_to_words / R

71000 becomes `seventy-one thousand`; 300019 becomes `three hundred thousand nineteen`; whole input 0 becomes `zero`. Below-one-thousand zero subparts return empty text and are omitted from composition, rather than injecting zero words. Tens/ones supply the hyphen in seventy-one, while nonempty thousand/remainder components are joined with single spaces.

under_thousand returns empty for zero subparts; whole-number conversion handles n==0 separately and joins only nonempty parts.

Evidence is from `main.R`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27.

- L1: `small_words <- function(number) {`
- L2: `units <- strsplit("zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen", " ")[[1]]`
- L3: `tens <- strsplit("zero ten twenty thirty forty fifty sixty seventy eighty ninety", " ")[[1]]`
- L4: `parts <- character(0)`
- L5: `hundreds <- number %/% 100`
- L6: `remainder <- number %% 100`
- L7: `if (hundreds > 0) parts <- c(parts, paste(units[hundreds + 1], "hundred"))`
- L8: `if (remainder >= 20) {`
- L9: `phrase <- tens[remainder %/% 10 + 1]`
- L10: `if (remainder %% 10 > 0) phrase <- paste0(phrase, "-", units[remainder %% 10 + 1])`
- L11: `parts <- c(parts, phrase)`
- L12: `} else if (remainder > 0) {`
- L13: `parts <- c(parts, units[remainder + 1])`
- L14: `}`
- L15: `paste(parts, collapse = " ")`
- L18: `number_words <- function(number) {`
- L19: `if (number == 0) {`
- L20: `return("zero")`
- L21: `}`
- L22: `parts <- character(0)`
- L23: `thousands <- number %/% 1000`
- L24: `remainder <- number %% 1000`
- L25: `if (thousands > 0) parts <- c(parts, paste(small_words(thousands), "thousand"))`
- L26: `if (remainder > 0) parts <- c(parts, small_words(remainder))`
- L27: `paste(parts, collapse = " ")`

Minimization: The small-number helper, thousand composition and named final word result are needed for these three cases. Other input literals and numeric-prefix output are not necessary to derive the word expressions. The selected complete original lines, in source order, cost 483 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 486, and the complete source costs 582. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
