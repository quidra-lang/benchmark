# Task B: 02_celsius_to_fahrenheit / J

The loop binding supplies the same current Celsius value to the arithmetic and to the left-hand output field. At -3, multiplication gives -27 and real division by 5 gives -5.4, then adding 32 gives 26.6. The completed line is `-3 C = 26.6 F`. One-decimal formatting controls display only; it is not the temperature conversion.

for_celsius. binds each scalar from the input vector. J % performs real/rational division, and the celsius reference remains available in the concatenated output.

Evidence is from `main.ijs`, L2,L3,L4.

- L2: `for_celsius. _40 _15 _3 0 22 37 100 do.`
- L3: `fahrenheit =. ((celsius * 9) % 5) + 32`
- L4: `smoutput (, '0' 8!:2 celsius), ' C = ', (, '1' 8!:2 fahrenheit), ' F'`

Minimization: The input/loop binding, conversion and output are the entire dependency chain for this line. Other temperatures need no separate trace. The selected complete original lines, in source order, cost 102 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 102, and the complete source costs 122. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
