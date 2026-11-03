# Task B selection: 00_array_mean / Kotlin

## Common answer requirements

1. Identify the existing sum/mean and original-length denominator that must change.
2. Sum and count only elements at least 50; choose zero before division when that count is zero.
3. Leave the seven input values and existing single-line two-decimal presentation unchanged.

## Answer supported by the excerpt

Replace the all-element aggregate with the sum and count of qualifying elements. Divide by the qualifying count, not the original length; select numeric zero when the count is zero. Keep the existing real-valued result and output formatter. In explicit accumulation versions, retain the original traversal length and introduce a separate qualifying count, so filtering does not shorten traversal.

## Source evidence and dependencies

Selected `main.kt` lines: 5. The excerpt preserves these complete lines in their original order and indentation.

The retained aggregate, accumulator initialization/updates where present, and division identify the change sites. The original-length expression is necessary to distinguish the existing denominator from the new qualifying count. Output lines are retained only where the calculation shares their physical line. Unchanged literal inputs and a separate formatter do not affect how to replace the aggregation.

## Language semantics and minimization

Use the language's ordinary evaluation, indexing, iteration and numeric semantics, and the documented behavior of the standard-library operations visible in the excerpt. The Task B assumptions apply; this is not a build or correctness verification. A filter at the input declaration is an alternative design, but would obscure the requirement to retain the original input and needs the aggregation site as well to handle the empty case. Selecting the aggregation/dependent division sites is sufficient with fewer source tokens. A standalone output call cannot reveal how the mean is obtained.

The selected excerpt contains **24 tokens** under `metric/tokenizer.py`. The contiguous source span from its first through last selected line contains 24 tokens; the complete source contains 82 tokens. These counts compare source-line sets, not LLM billing. Boilerplate and unchanged processing are omitted when they contribute no required fact. The excerpt need not be a standalone compilable program; omitted closing delimiters are not evidence for additional behavior.
