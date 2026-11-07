# Task B: 43_run_length_encoding / Julia

The second input is twelve W, then B, then twelve W, then BBB. Maximal-run encoding produces `12W1B12W3B`. Decoding scans each complete decimal count, so 12 is one count rather than separate 1 and 2; repetition reconstructs `WWWWWWWWWWWWBWWWWWWWWWWWWBBB`. The full line is `WWWWWWWWWWWWBWWWWWWWWWWWWBBB -> 12W1B12W3B -> WWWWWWWWWWWWBWWWWWWWWWWWWBBB`. The named decoded value is obtained from encoded, not from copying the original.

The regex encoder matches maximal repeated-letter runs; the decoder regex captures multi-digit counts and the following symbol, then join constructs a new string.

Evidence is from `main.jl`, L1,L2,L4,L5,L6,L7,L9,L11,L15,L16,L17,L18,L19.

- L1: `encode(source) =`
- L2: `join(string(length(m.match), first(m.match)) for m in eachmatch(r"([A-Z])\1*", source))`
- L4: `decode(encoded) = replace(`
- L5: `encoded,`
- L6: `r"[0-9]+[A-Z]" => run -> repeat(string(run[end]), parse(Int, run[1:(end-1)])),`
- L7: `)`
- L9: `for source in [`
- L11: `"WWWWWWWWWWWWBWWWWWWWWWWWWBBB",`
- L15: `]`
- L16: `encoded = encode(source)`
- L17: `decoded = decode(encoded)`
- L18: `println(source, " -> ", encoded, " -> ", decoded)`
- L19: `end`

Minimization: The encoder and decoder bodies, this input binding and their call/output chain are needed. Other sample literals are omitted when independent complete lines permit it. The selected complete original lines, in source order, cost 187 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 213, and the complete source costs 213. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
