# Task B: 26_caesar_cipher / J

The shift operation maps letters within their own uppercase/lowercase alphabet using modulo 26, so Z with shift 3 wraps to C. The following comma is not a letter and is carried through unchanged. The produced ciphertext, not the original message, is supplied to the same operation with shift -3 for decryption.

The helper searches the combined alphabets, chooses a case-specific base, appends shifted or unchanged characters to result, and returns result. Concatenation rebinds a new character value; it does not mutate the caller message.

Evidence is from `main.ijs`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L16,L17,L19.

- L1: `caesar =: 4 : 0`
- L2: `alphabet =. 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'`
- L3: `result =. ''`
- L4: `for_char. y do.`
- L5: `index =. alphabet i. char`
- L6: `if. index<52 do.`
- L7: `base =. 26*index>:26`
- L8: `shifted =. base + 26 | (index-base)+x`
- L9: `result =. result,shifted{alphabet`
- L10: `else.`
- L11: `result =. result,char`
- L12: `end.`
- L13: `end.`
- L14: `result`
- L16: `message =: 'Zoe, meet Max by the Old Bridge at six!'`
- L17: `encrypted =: 3 caesar message`
- L19: `smoutput _3 caesar encrypted`

Minimization: The complete small shift helper is needed because its case/wrap/nonletter behavior is user-defined. The encryption binding and decryption call establish the value crossing that boundary; unrelated printing is omitted where separately written. The selected complete original lines, in source order, cost 175 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 181, and the complete source costs 181. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
