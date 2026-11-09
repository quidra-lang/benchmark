# Task B: 67_base64_encode / Julia

ASCII bytes are packed in groups of three with missing final bytes treated as zero bits, then split into four six-bit alphabet indices. `Hello, World!` has 13 bytes: its last single byte ! creates `IQ==`. Suppress just the two emitted equals signs while preserving those zero-filled bits; the quoted completed line becomes `"Hello, World!" -> "SGVsbG8sIFdvcmxkIQ"`. `Man` remains TWFu because all three bytes are present, and empty input remains empty.

The custom encode function uses codeunits, zero-filled missing bytes and count-dependent = branches. Omit only those padding output characters before the common quoted println.

Evidence is from `main.jl`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L18,L19,L20,L21.

- L1: `function encode64(source)`
- L2: `alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"`
- L3: `bytes = codeunits(source)`
- L4: `output = IOBuffer()`
- L5: `for first = 1:3:length(bytes)`
- L6: `remaining = min(3, length(bytes)-first+1)`
- L7: `value = 0`
- L8: `for offset = 0:2`
- L9: `value = value*256+(offset < remaining ? Int(bytes[first+offset]) : 0)`
- L10: `end`
- L11: `for (offset, divisor) in enumerate([262144, 4096, 64, 1])`
- L12: `print(output, offset <= remaining+1 ? alphabet[div(value, divisor)%64+1] : '=')`
- L13: `end`
- L14: `end`
- L15: `return String(take!(output))`
- L18: `for source in ["Man", "Hello, World!", "", "<b>bold</b>", "a+b=c?"]`
- L19: `encoded = encode64(source)`
- L20: `println('"', source, "\" -> \"", encoded, '"')`
- L21: `end`

Minimization: The complete small byte encoder, final-partial-group decisions and named output call are necessary to explain this end-to-end change. Other test cases do not require separate encoding traces. The selected complete original lines, in source order, cost 323 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 326, and the complete source costs 326. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
