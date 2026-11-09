# Task B: 26_caesar_cipher / Julia

The shift operation maps letters within their own uppercase/lowercase alphabet using modulo 26, so Z with shift 3 wraps to C. The following comma is not a letter and is carried through unchanged. The produced ciphertext, not the original message, is supplied to the same operation with shift -3 for decryption.

map visits characters and constructs a new String from case-specific shifted characters or the unchanged character. Julia strings are immutable; the new cipher binding is passed to caesar(cipher,-3).

Evidence is from `main.jl`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L13,L15.

- L1: `function caesar(message, shift)`
- L2: `return map(message) do c`
- L3: `if 'A' <= c <= 'Z'`
- L4: `Char(Int('A') + mod(Int(c)-Int('A')+shift, 26))`
- L5: `elseif 'a' <= c <= 'z'`
- L6: `Char(Int('a') + mod(Int(c)-Int('a')+shift, 26))`
- L7: `else`
- L8: `c`
- L9: `end`
- L10: `end`
- L11: `end`
- L13: `ciphertext = caesar("Zoe, meet Max by the Old Bridge at six!", 3)`
- L15: `println(caesar(ciphertext, -3))`

Minimization: The complete small shift helper is needed because its case/wrap/nonletter behavior is user-defined. The encryption binding and decryption call establish the value crossing that boundary; unrelated printing is omitted where separately written. The selected complete original lines, in source order, cost 192 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 198, and the complete source costs 198. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
