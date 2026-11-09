# Task B: 43_run_length_encoding / R

The second input is twelve W, then B, then twelve W, then BBB. Maximal-run encoding produces `12W1B12W3B`. Decoding scans each complete decimal count, so 12 is one count rather than separate 1 and 2; repetition reconstructs `WWWWWWWWWWWWBWWWWWWWWWWWWBBB`. The full line is `WWWWWWWWWWWWBWWWWWWWWWWWWBBB -> 12W1B12W3B -> WWWWWWWWWWWWBWWWWWWWWWWWWBBB`. The named decoded value is obtained from encoded, not from copying the original.

rle forms maximal runs; the decoder captures [0-9]+ counts, converts those complete strings and repeats their associated symbols.

Evidence is from `main.R`, L1,L2,L3,L4,L6,L7,L8,L9,L11,L12,L13,L14,L15,L16,L17,L18,L19.

- L1: `encode <- function(source) {`
- L2: `runs <- rle(strsplit(source, "", fixed = TRUE)[[1]])`
- L3: `paste(paste0(runs$lengths, runs$values), collapse = "")`
- L4: `}`
- L6: `decode <- function(encoded) {`
- L7: `runs <- regmatches(encoded, gregexpr("[0-9]+[A-Z]", encoded))[[1]]`
- L8: `paste(strrep(sub("[0-9]+", "", runs), as.integer(sub("[A-Z]", "", runs))), collapse = "")`
- L9: `}`
- L11: `sources <- c(`
- L12: `"AAABBBCCCD", "WWWWWWWWWWWWBWWWWWWWWWWWWBBB", "ALGORITHM", "MISSISSIPPI",`
- L13: `"XXXXXXXXXXYYYYYYYYYYYYYYYYYYYYYZ"`
- L14: `)`
- L15: `for (source in sources) {`
- L16: `encoded <- encode(source)`
- L17: `decoded <- decode(encoded)`
- L18: `cat(sprintf("%s -> %s -> %s\n", source, encoded, decoded))`
- L19: `}`

Minimization: The encoder and decoder bodies, this input binding and their call/output chain are needed. Other sample literals are omitted when independent complete lines permit it. The selected complete original lines, in source order, cost 271 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 273, and the complete source costs 273. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
