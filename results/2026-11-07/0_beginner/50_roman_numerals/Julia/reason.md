# Task B: 50_roman_numerals / Julia

Encoding 1994 greedily appends M,CM,XC,IV as remaining becomes 994,94,4,0, producing MCMXCIV. The decoder receives that generated string. It maps symbols to 1000,100,1000,10,100,1,5 and subtracts a value only when followed by a greater one: 1000-100+1000-10+100-1+5=1994. Thus the numeric-to-Roman operation and Roman-to-numeric operation are separate stages joined by the encoded string.

The encoder constructs roman by repeated symbol append/subtraction; from_roman reads roman from to_roman(number), not number itself.

Evidence is from `main.jl`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L26,L27,L28,L29,L30,L31,L32,L33,L37,L38.

- L1: `function to_roman(number)`
- L2: `result = ""`
- L3: `for (value, symbol) in [`
- L4: `(1000, "M"),`
- L5: `(900, "CM"),`
- L6: `(500, "D"),`
- L7: `(400, "CD"),`
- L8: `(100, "C"),`
- L9: `(90, "XC"),`
- L10: `(50, "L"),`
- L11: `(40, "XL"),`
- L12: `(10, "X"),`
- L13: `(9, "IX"),`
- L14: `(5, "V"),`
- L15: `(4, "IV"),`
- L16: `(1, "I"),`
- L17: `]`
- L18: `while number >= value`
- L19: `result *= symbol`
- L20: `number -= value`
- L21: `end`
- L22: `end`
- L23: `return result`
- L26: `function from_roman(roman)`
- L27: `table = Dict('I'=>1, 'V'=>5, 'X'=>10, 'L'=>50, 'C'=>100, 'D'=>500, 'M'=>1000)`
- L28: `total = 0`
- L29: `for i = 1:length(roman)`
- L30: `value = table[roman[i]]`
- L31: `total += i < length(roman) && value < table[roman[i+1]] ? -value : value`
- L32: `end`
- L33: `return total`
- L37: `roman = to_roman(number)`
- L38: `println(number, " -> ", roman, " -> ", from_roman(roman))`

Minimization: The conversion tables, complete encoder/decoder algorithms and the call boundary are needed to trace this subtractive case. Unrelated input literals/output labels are omitted where independent lines allow it. The selected complete original lines, in source order, cost 443 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 494, and the complete source costs 496. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
