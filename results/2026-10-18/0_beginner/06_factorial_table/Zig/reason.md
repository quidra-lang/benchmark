# Task B selection: 06_factorial_table / Zig

## Answer requirements

Locate the factorial range and determine which representation, operations or output would need to change to preserve exact results through 15!.

## Evidence and answer

The counter starts at zero and the while condition changes its inclusive bound from 12 to 15; the counter can remain u32. The u32 accumulator is too narrow for 15! = 1307674368000, so widen it to u64. Zig can coerce the u32 multiplication operand to the wider u64 peer type, and the standard decimal formatter already handles u64, so neither the update nor the output line changes.

## Minimization

Selected complete lines of `main.zig`: 7, 8, 9. The excerpt preserves their text, indentation and order.

The loop header alone does not reveal the integer representation. Selecting the full loop body adds unchanged calculations or output that do not introduce another edit. The previous excerpt contained 60 tokens; the selected excerpt contains **50 tokens** using `metric/tokenizer.py`.
