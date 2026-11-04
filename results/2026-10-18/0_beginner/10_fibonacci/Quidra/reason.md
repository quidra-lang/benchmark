# Task B selection: 10_fibonacci / Quidra

## Answer requirements

Extend the exact Fibonacci term generation and its linked sum to 40 terms, preserving output.

## Evidence and answer

The inclusive loop endpoint is the single bound to change from 30 to 40. The explicit int seed values and tuple assignment identify the Fibonacci recurrence; the total adds a before advancing the pair inside that same loop. Quidra int is exact arbitrary precision, so neither state nor total requires widening. F(40) is 102334155 and the sum is 267914295. The unchanged per-term print, spacing and final label already use this state and total; no separate output-bound change is needed.

## Minimization

Selected complete lines of `main.qui`: 1, 2, 3, 4, 8, 9. The excerpt preserves their text, indentation and order.

The loop header alone cannot establish that the same iteration updates the total. Adding the print calls only shows existing formatting, which the proposed change does not touch. The previous excerpt contained 88 tokens; the selected excerpt contains **67 tokens** using `metric/tokenizer.py`.
