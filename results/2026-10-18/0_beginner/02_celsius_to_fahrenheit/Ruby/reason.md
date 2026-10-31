# Task B selection: 02_celsius_to_fahrenheit / Ruby

## Common answer requirements

1. Locate the iteration where output can be restricted to Celsius values strictly below zero.
2. Retain the original input and order and leave conversion and per-line formatting unchanged.

## Answer supported by the excerpt

At the existing per-temperature iteration, admit its body only when the current Celsius value is strictly below zero. Keep the input collection and iteration order, and leave the existing conversion and output body intact. This removes zero and positive temperatures without changing the conversion formula or formatter.

## Source evidence and dependencies

Selected `main.rb` lines: 2. The excerpt preserves these complete lines in their original order and indentation.

The iteration header identifies both the ordered collection and the Celsius item to test, hence the insertion point and the value used by the strict predicate. In the indexed C version the output line is additionally necessary to establish celsius[i] as that value. No change is proposed inside the retained original body, so copying the unrelated conversion/formatter would not help locate or explain this guard.

## Language semantics and minimization

Use the language's ordinary evaluation, indexing, iteration and numeric semantics, and the documented behavior of the standard-library operations visible in the excerpt. The Task B assumptions apply; this is not a build or correctness verification. Filtering the literal array would require selecting that longer declaration and would alter the input itself. Selecting conversion and output lines is another larger context candidate but does not improve the loop-guard explanation. The selected loop site supports the requested change while preserving all other processing.

The selected excerpt contains **10 tokens** under `metric/tokenizer.py`. The contiguous source span from its first through last selected line contains 10 tokens; the complete source contains 96 tokens. These counts compare source-line sets, not LLM billing. Boilerplate and unchanged processing are omitted when they contribute no required fact. The excerpt need not be a standalone compilable program; omitted closing delimiters are not evidence for additional behavior.
