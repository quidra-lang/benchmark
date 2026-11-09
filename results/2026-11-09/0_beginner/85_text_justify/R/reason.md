# Task B: 85_text_justify / R

Splitting only on word-separating spaces retains punctuation: `names,` is one six-character token, including its comma. Greedy packing accepts a word only when letter lengths plus at least one space per existing gap fit width 30; otherwise it closes the current line and starts a fresh one. For a nonfinal multiword line, total spaces=30-sum(word lengths), gaps=word count-1, base=spaces quotient gaps, extra=spaces remainder gaps. Every gap receives base spaces and the leftmost extra gaps one more, giving exactly 30 characters. Vertical bars frame the completed text. Final/single-word lines instead join with ordinary single spaces and pad on the right to width 30.

strsplit(...," ",fixed=TRUE) retains punctuation. letters+length(current)+nchar(word) is packing width; %/% and %% plus the padding vector distribute gaps, with zero padding after the last word.

Evidence is from `main.R`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29.

- L1: `width <- 30`
- L2: `paragraph <- "Good software is written for people first and for machines second. A clear program explains its purpose through careful names, small functions and honest tests. When a team agrees on shared rules for internationalization, documentation and code review, every newcomer can read the code quickly, change it safely and ship new improvements with confidence instead of fear, week after week."`
- L3: `lines <- list()`
- L4: `current <- character(0)`
- L5: `letters <- 0`
- L6: `for (word in strsplit(paragraph, " ", fixed = TRUE)[[1]]) {`
- L7: `if (length(current) > 0 && letters + length(current) + nchar(word) > width) {`
- L8: `lines[[length(lines) + 1]] <- current`
- L9: `current <- character(0)`
- L10: `letters <- 0`
- L11: `}`
- L12: `current <- c(current, word)`
- L13: `letters <- letters + nchar(word)`
- L14: `}`
- L15: `lines[[length(lines) + 1]] <- current`
- L16: `for (number in seq_along(lines)) {`
- L17: `words <- lines[[number]]`
- L18: `if (number == length(lines) || length(words) == 1) {`
- L19: `line <- sprintf("%-*s", width, paste(words, collapse = " "))`
- L20: `} else {`
- L21: `spaces <- width - sum(nchar(words))`
- L22: `gaps <- length(words) - 1`
- L23: `base <- spaces %/% gaps`
- L24: `extra <- spaces %% gaps`
- L25: `padding <- strrep(" ", c(base + (seq_len(gaps) <= extra), 0))`
- L26: `line <- paste0(words, padding, collapse = "")`
- L27: `}`
- L28: `cat("|", line, "|\n", sep = "")`
- L29: `}`

Minimization: Paragraph/token binding, greedy state transitions, final-line branch, quotient/remainder distribution and framing are necessary for this routine. No individual paragraph line needs a full formatting trace. The selected complete original lines, in source order, cost 548 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 548, and the complete source costs 548. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
