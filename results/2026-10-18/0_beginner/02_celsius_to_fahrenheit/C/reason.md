# Task B selection: 02_celsius_to_fahrenheit / C

## Answer requirements

Locate the ordered conversion loop and identify the guard that keeps only strictly negative Celsius inputs.

## Evidence and answer

The celsius declaration identifies the original indexed collection and the loop establishes its ordered indices 0 through 6. Insert a guard for celsius[i] < 0 at the start of the body. This alternative retains the declaration and indexed loop in place of the longer unchanged printf/calculation line. It also shows directly that -40, -15 and -3 pass in that order, while zero does not.

Keep the original input, computation and formatter. Testing the current Celsius value before the conversion/output leaves exactly the three negative values in original order.

## Minimization

Selected complete lines of `main.c`: 4, 5. The excerpt preserves their text, indentation and order.

The indexed loop alone leaves its input collection unspecified; the declaration-plus-loop candidate supplies that connection with fewer tokens than the loop-plus-printf candidate. The previous excerpt contained 80 tokens; the selected excerpt contains **66 tokens** using `metric/tokenizer.py`.
