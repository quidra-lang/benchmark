# Task B: 58_morse_code / Julia

The decoder should take Morse text as its message input, split words on the existing slash delimiter, split each word into complete space-delimited letter-code tokens, perform exact reverse lookup, then join decoded letters without separators and decoded words with one space. Thus `.` maps independently to E and `.-` to A; no prefix match or original-letter fallback is appropriate. The existing stages already meet these matching/joining requirements; only expose their encoded-input boundary as needed.

The reverse Dict is keyed by complete code strings; split(encoded," / ") then split(word) feeds exact reverse-table indexing and nested joins.

Evidence is from `main.jl`, L1,L2,L3,L4,L5,L6,L9,L10,L11,L12.

- L1: `alphabet = collect("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")`
- L2: `codes = split(`
- L3: `".- -... -.-. -.. . ..-. --. .... .. .--- -.- .-.. -- -. --- .--. --.- .-. ... - ..- ...- .-- -..- -.-- --.. ----- .---- ..--- ...-- ....- ..... -.... --... ---.. ----.",`
- L4: `)`
- L5: `table = Dict(zip(alphabet, codes))`
- L6: `reverse_table = Dict(code=>string(letter) for (letter, code) in table)`
- L9: `decoded = join(`
- L10: `(join(reverse_table[code] for code in split(word)) for word in split(encoded, " / ")),`
- L11: `" ",`
- L12: `)`

Minimization: The code/letter association and complete decode path establish exact-token semantics and word restoration. Encoding from original message letters is intentionally omitted because it cannot justify an input-only decoder. The selected complete original lines, in source order, cost 232 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 305, and the complete source costs 315. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
