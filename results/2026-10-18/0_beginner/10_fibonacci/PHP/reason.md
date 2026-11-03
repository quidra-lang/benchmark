# Task B selection: 10_fibonacci / PHP

## Common answer requirements

1. Locate the term-count limit and the dependency connecting generated terms to their sum.
2. Preserve exact integer values, ordering, spacing and the existing sum label for exactly forty terms.

## Answer supported by the excerpt

Change the term-count limit from 30 to 40. In list implementations, keep summing the resulting list; in streaming implementations, keep the sum update inside that same forty-iteration loop before advancing the Fibonacci state. F(40)=102334155 and the forty-term sum is 267914295. Even the final next-state value computed by these loops fits signed 32-bit, so the existing 32-bit integer representations do not require widening for this change. Arbitrary-precision and binary64-number versions also retain exact integer values at this bound.

## Source evidence and dependencies

Selected `main.php` lines: 3-6,9. The excerpt preserves these complete lines in their original order and indentation.

The initial integer state or typed collection identifies the representation; the bound identifies the extent change. The append/recurrence and sum sites show that the total follows the same generated terms rather than a separate thirty-element bound. Unchanged per-term spacing and the output label are not independent change sites.

## Language semantics and minimization

Use the language's ordinary evaluation, indexing, iteration and numeric semantics, and the documented behavior of the standard-library operations visible in the excerpt. The Task B assumptions apply; this is not a build or correctness verification. Selecting only the count literal would not expose a separately bounded summation or a numeric representation issue. Selecting final output alone would not show how many terms are generated. The retained extent and dependent sum/representation sites provide the sufficient smaller union.

The selected excerpt contains **98 tokens** under `metric/tokenizer.py`. The contiguous source span from its first through last selected line contains 120 tokens; the complete source contains 125 tokens. These counts compare source-line sets, not LLM billing. Boilerplate and unchanged processing are omitted when they contribute no required fact. The excerpt need not be a standalone compilable program; omitted closing delimiters are not evidence for additional behavior.
