# Task B selection: 02_celsius_to_fahrenheit / Quidra

## Common answer requirements

1. Identify the iteration where a strictly-below-zero guard must be added.
2. Retain the original ordered inputs, conversion calculation, one-decimal presentation and newline behavior.

## Implementation decision

Use explicitly typed exact real arithmetic. The original real64 cast has a fallible success/error type and fails to provide the unique real context required by the following literal in this compiler. Exact real is permitted by Task A, which does not mandate IEEE-754. The formula and its order are unchanged; every integer Celsius input produces an exact tenth, so one-decimal formatting satisfies the half-up output requirement without a tie. Unlike topic 03, this topic has no double-precision contract.

## Evidence and answer

The collection header identifies the current Celsius value and the insertion point for a guard. Leave its conversion and print body unchanged. The input list and unchanged body do not supply another required modification site.

## Selection and minimization

Selected complete main.qui lines: 2. Every selected line is copied verbatim, once per source location and in source order. The excerpt is not required to compile independently. The stated Task B assumptions, language guarantees and documented first-party library semantics apply. The full source or contiguous context span is a larger alternative; unchanged unrelated input, processing and formatting are omitted when they supply no answer requirement. This is a reviewed minimum among the identified alternatives, not a proof of a global mathematical optimum.

Using unchanged metric/tokenizer.py: Task A 106 → 106; Task B 11 → 11. Compiler and native-output validation is recorded separately; token or verbatim checks alone do not establish compilation or correctness.
