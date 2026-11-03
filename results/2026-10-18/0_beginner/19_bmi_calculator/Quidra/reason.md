# Task B selection: 19_bmi_calculator / Quidra

## Common answer requirements

1. Identify Mika's height and weight, integer numerator and denominator, and the single real division.
2. Trace the threshold comparisons that classify the unrounded BMI.
3. Explain that one-decimal formatting affects display without changing classification.

## Implementation decision

Represent each person as an explicitly typed (string, int, int) record, one record per line, rather than three parallel arrays and a hardcoded index limit. The value loop binds related data together. Use explicitly typed exact real for BMI: Task A requires integer products followed by one real division and does not mandate IEEE-754. This corrects the baseline's incompatible fallible real64 cast expressions and ensures exact comparison of the unrounded rational value. All specified data, arithmetic order and thresholds remain unchanged.

## Evidence and answer

The record type, Mika record and value-loop binder associate Mika with height 165 and weight 70. The integer products give numerator 700000 and denominator 27225; exact real division gives about 25.7116620753. The first two threshold tests fail and the bmi < 30.0 branch selects overweight. The print line formats the same bmi as 25.7 after classification; no rounded value is assigned back. The obese fallback is unreachable for Mika and is omitted; other people are irrelevant to this focused trace. Language value semantics and explicit numeric types are sufficient; no user helper implementations are elided.

## Selection and minimization

Selected complete main.qui lines: 1, 4, 8, 9, 10, 11, 12, 13, 14, 15, 17, 18. Every selected line is copied verbatim, once per source location and in source order. The excerpt is not required to compile independently. The stated Task B assumptions, language guarantees and documented first-party library semantics apply. The full source or contiguous context span is a larger alternative; unchanged unrelated input, processing and formatting are omitted when they supply no answer requirement. This is a reviewed minimum among the identified alternatives, not a proof of a global mathematical optimum.

Using unchanged metric/tokenizer.py: Task A 271 → 282; Task B 253 → 203. Compiler and native-output validation is recorded separately; token or verbatim checks alone do not establish compilation or correctness.
