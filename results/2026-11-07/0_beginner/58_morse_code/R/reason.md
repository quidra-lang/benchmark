# Task B: 58_morse_code / R

The decoder should take Morse text as its message input, split words on the existing slash delimiter, split each word into complete space-delimited letter-code tokens, perform exact reverse lookup, then join decoded letters without separators and decoded words with one space. Thus `.` maps independently to E and `.-` to A; no prefix match or original-letter fallback is appropriate. The existing stages already meet these matching/joining requirements; only expose their encoded-input boundary as needed.

The reverse table is indexed by complete strings from split(...," / ") and split(...," "); the final paste collapses letters and restores word spaces.

Evidence is from `main.R`, L1,L2,L4,L9,L10,L11.

- L1: `alphabet <- strsplit("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", "", fixed = TRUE)[[1]]`
- L2: `codes <- strsplit(".- -... -.-. -.. . ..-. --. .... .. .--- -.- .-.. -- -. --- .--. --.- .-. ... - ..- ...- .-- -..- -.-- --.. ----- .---- ..--- ...-- ....- ..... -.... --... ---.. ----.", " ", fixed = TRUE)[[1]]`
- L4: `reverse_table <- setNames(alphabet, codes)`
- L9: `decoded <- paste(vapply(strsplit(encoded, " / ", fixed = TRUE)[[1]], function(word) {`
- L10: `paste(reverse_table[strsplit(word, " ", fixed = TRUE)[[1]]], collapse = "")`
- L11: `}, character(1)), collapse = " ")`

Minimization: The alphabet/code mapping and reverse_table are required to distinguish full tokens . and .-. The word split, letter-token split, reverse lookup, letter concatenation and word join establish all decoder requirements. The forward table is used only by the omitted encoder and adds no decoder evidence, so it is excluded. Complete source lines remain verbatim and ordered. This is source review, not a program build or run.
