# Task B selection: 50_roman_numerals / C++

## Common answer requirements

Trace encoding and decoding for 1994, identifying the subtractive pair thresholds and the signed contributions to the decoder.

## Source evidence

The ordered thresholds and append/subtract loop produce M, CM, XC, IV, taking the remainder 1994 → 994 → 94 → 4 → 0. CM, XC, and IV are appended whole as two-character table entries. The decoder lookup and comparison give negative contributions to a smaller digit before a larger digit. The decoder walks left to right: M adds 1000, C before M subtracts 100 (900), M adds 1000 (1900), X before C subtracts 10 (1890), C adds 100 (1990), I before V subtracts 1 (1989), and final V adds 5 (1994).

## Minimization

The selected table entries establish the greedy thresholds and actual decoded digits. After the remainder reaches zero, a separate value-one row cannot contribute; packed entries are kept verbatim when sharing a line with necessary data. The question supplies 1994.

Selected complete lines of `main.cpp`: 5–9, 11, 13, 15–16, 19–21, 23–33. The prior excerpt measured 489 tokens; this excerpt measures 485 with `metric/tokenizer.py`.

## Current token measurement

Task A: **666 tokens**. Task B: **483 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
