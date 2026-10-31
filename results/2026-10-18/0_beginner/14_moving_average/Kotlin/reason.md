# Task B selection: 14_moving_average / Kotlin

## Common answer requirements

1. Locate the first eligible day/index, five-element window and real-valued divisor.
2. Preserve the last day10, six ordered result lines and the existing two-decimal formatting/labels.

## Answer supported by the excerpt

Begin at day5, or zero-based index4. Expand each window to days d-4 through d and divide its sum by5 using real division; a mean primitive already divides by the selected window length. Keep the last-day limit and formatter. Where a window iterator is paired with an output index, change both its window length and day-offset from3 to5. These domains contain exactly six consecutive days through day10.

## Source evidence and dependencies

Selected `main.kt` lines: 5,6. The excerpt preserves these complete lines in their original order and indentation.

The iteration start controls which days appear; the slice or explicit addends control which five values contribute; the divisor or mean operation controls the average. A zero-based output offset is retained when it is needed to connect the changed index to the day label. Other sales values, fixed display settings and wrapper code are unchanged.


Independent minimization removed unchanged output line(s) 7: the bound/window/divisor edits do not alter their index+1 label or formatting, so those lines supply no additional modification site. The former sufficient excerpt cost 95 tokens; the revised excerpt costs 62 tokens.

## Language semantics and minimization

Use the language's ordinary evaluation, indexing, iteration and numeric semantics, and the documented behavior of the standard-library operations visible in the excerpt. The Task B assumptions apply; this is not a build or correctness verification. Changing only the denominator would still sum three days, and changing only the slice could access missing preceding days. The selected bounds/window/division sites therefore form the necessary dependency set. A generic mean implementation or unrelated input declaration is a larger alternative with no additional required edit.

The selected excerpt contains **62 tokens** under `metric/tokenizer.py`. The contiguous source span from its first through last selected line contains 62 tokens; the complete source contains 177 tokens. These counts compare source-line sets, not LLM billing. Boilerplate and unchanged processing are omitted when they contribute no required fact. The excerpt need not be a standalone compilable program; omitted closing delimiters are not evidence for additional behavior.
