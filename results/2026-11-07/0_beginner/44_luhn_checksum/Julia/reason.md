# Task B: 44_luhn_checksum / Julia

The original membership number stays a string, retaining its leading 0. Scanning from the right leaves the check digit 4 undoubled; every second digit from there is doubled and reduced by 9 if above 9. The transformed sum is 42, so it is invalid. Removing the current check digit gives 38, and the replacement is (-38) mod 10 =2. The completed line is `0128469655154: invalid (expected check digit 2)`.

enumerate(reverse(number)) is one-based, so iseven(position) doubles positions 2,4,...; Int(c)-Int('0') converts individual digits without converting the stored number.

Evidence is from `main.jl`, L1,L3,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23.

- L1: `for number in [`
- L3: `"0128469655154",`
- L8: `]`
- L9: `total = 0`
- L10: `for (position, c) in enumerate(reverse(number))`
- L11: `value = Int(c)-Int('0')`
- L12: `if iseven(position)`
- L13: `value *= 2`
- L14: `value = value > 9 ? value-9 : value`
- L15: `end`
- L16: `total += value`
- L17: `end`
- L18: `if total % 10 == 0`
- L19: `println(number, ": valid")`
- L20: `else`
- L21: `expected = mod(-(total-(Int(number[end])-Int('0'))), 10)`
- L22: `println(number, ": invalid (expected check digit ", expected, ")")`
- L23: `end`

Minimization: The literal string and the entire local transform/check/output block establish leading-zero preservation, parity and exact line. Other number literals can be omitted when separately written. The selected complete original lines, in source order, cost 228 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 326, and the complete source costs 328. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
