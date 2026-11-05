# Task B selection: 02_celsius_to_fahrenheit / Quidra

## Common answer requirements

1. Identify the iteration where a strictly-below-zero guard must be added.
2. Retain the original ordered inputs, conversion calculation, one-decimal presentation and newline behavior.

## Implementation decision

The expression `celsius * 1.8 + 32` uses exact `real` arithmetic. The literal `1.8` equals nine fifths, and the mixed numeric operations convert the integers to `real`. Every Celsius input in the task gives an exact tenth, so one-decimal formatting satisfies the half-up output requirement without a tie.

## Evidence and answer

The collection header identifies the current Celsius value and the insertion point for a guard. Leave its conversion and print body unchanged. The input list and unchanged body do not supply another required modification site.

## Selection and minimization

Selected complete main.qui lines: 2. Every selected line is copied verbatim, once per source location and in source order. The excerpt is not required to compile independently. The stated Task B assumptions, language guarantees and documented first-party library semantics apply. The full source or contiguous context span is a larger alternative; unchanged unrelated input, processing and formatting are omitted when they supply no answer requirement. This is a reviewed minimum among the identified alternatives, not a proof of a global mathematical optimum.

The source-code tokenizer `metric/tokenizer.py` counts 84 tokens for Task A and 9 for Task B.
