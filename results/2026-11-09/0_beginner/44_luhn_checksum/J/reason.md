# Task B: 44_luhn_checksum / J

The original membership number stays a string, retaining its leading 0. Scanning from the right leaves the check digit 4 undoubled; every second digit from there is doubled and reduced by 9 if above 9. The transformed sum is 42, so it is invalid. Removing the current check digit gives 38, and the replacement is (-38) mod 10 =2. The completed line is `0128469655154: invalid (expected check digit 2)`.

The digit vector stays in original order; (#digits)-i supplies right-position parity directly, while the original number binding supplies output. The checksum decision and replacement expression use the transformed sum.

Evidence is from `main.ijs`, L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14.

- L2: `numbers =. '688126340316';'0128469655154';'92181914514156';'177332430060552';'7982377590420309';'9884593615513906'`
- L3: `for_box. numbers do.`
- L4: `number =. >box`
- L5: `digits =. '0123456789'i.number`
- L6: `doubled =. digits * 1 + 0 = 2 | (#digits) - i.#digits`
- L7: `transformed =. doubled - 9 * doubled > 9`
- L8: `total =. +/transformed`
- L9: `result =. 'valid'`
- L10: `if. 0~:10|total do.`
- L11: `expected =. 10|10-10|total-{:digits`
- L12: `result =. 'invalid (expected check digit ',(":expected),')'`
- L13: `end.`
- L14: `smoutput number,': ',result`

Minimization: The literal string and the entire local transform/check/output block establish leading-zero preservation, parity and exact line. Other number literals can be omitted when separately written. The selected complete original lines, in source order, cost 292 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 292, and the complete source costs 312. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
