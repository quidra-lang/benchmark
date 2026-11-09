# Task B: 02_celsius_to_fahrenheit / Julia

The loop binding supplies the same current Celsius value to the arithmetic and to the left-hand output field. At -3, multiplication gives -27 and real division by 5 gives -5.4, then adding 32 gives 26.6. The completed line is `-3 C = 26.6 F`. One-decimal formatting controls display only; it is not the temperature conversion.

The for binding is celsius. / on integer operands yields a real quotient, and @printf uses the original binding alongside fahrenheit.

Evidence is from `main.jl`, L3,L4,L5.

- L3: `for celsius in [-40, -15, -3, 0, 22, 37, 100]`
- L4: `fahrenheit = celsius * 9 / 5 + 32`
- L5: `@printf("%d C = %.1f F\n", celsius, fahrenheit)`

Minimization: The input/loop binding, conversion and output are the entire dependency chain for this line. Other temperatures need no separate trace. The selected complete original lines, in source order, cost 85 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 85, and the complete source costs 92. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
