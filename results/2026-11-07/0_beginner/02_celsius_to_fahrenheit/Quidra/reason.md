# Task B selection: 02_celsius_to_fahrenheit / Quidra

## Answer requirements

For the input Celsius value -3, connect the iteration binding, Fahrenheit calculation and construction of the conversion line. Explain how the current-temperature name or parameter resolves at each stage, how the calculation retains its fractional part, and how the same original Celsius value reaches the left side of the output. Derive that one line from the source and distinguish the numeric conversion from display formatting.

## Answer and source evidence

The loop binding supplies the same Celsius value to the arithmetic and left-hand output field. With celsius=-3, -3*1.8+32=26.6, so the line is `-3 C = 26.6 F`. The decimal multiplier preserves a fractional numeric result; the one-place formatter converts it to display text. The question supplies the input -3, so the separate input collection is unnecessary.



Selected `main.qui` lines: 2, 3, 4. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
