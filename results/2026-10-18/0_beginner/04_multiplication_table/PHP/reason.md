# Task B selection: 04_multiplication_table / PHP

## Common answer requirements

1. Locate both row and column limits and the current product-field width.
2. Explain the change to 1 through 12 and width four while retaining ascending products and existing row termination.

## Answer supported by the excerpt

Extend both iteration domains to include 12 (an exclusive upper bound becomes 13; an inclusive bound becomes 12), or extend the shared factor vector to twelve elements. Increase the right-aligned field width from three to four. Products remain in increasing column order. Left padding places spaces before each number, not after the last number, so the existing end-of-row newline produces twelve lines without trailing spaces.

## Source evidence and dependencies

Selected `main.php` lines: 3-5. The excerpt preserves these complete lines in their original order and indentation.

The row bound, column bound (or shared factors) and padding width are the only independent change sites. The product expression is retained when on the same line as those sites. A separate unchanged multiplication or end-of-row call adds no information about these edits.

## Language semantics and minimization

Use the language's ordinary evaluation, indexing, iteration and numeric semantics, and the documented behavior of the standard-library operations visible in the excerpt. The Task B assumptions apply; this is not a build or correctness verification. Changing the input domain alone leaves the wrong field width; changing only the formatter leaves a nine-by-nine table. The selected bounds plus width therefore beat either incomplete alternative and avoid copying the full output routine.

The selected excerpt contains **74 tokens** under `metric/tokenizer.py`. The contiguous source span from its first through last selected line contains 74 tokens; the complete source contains 93 tokens. These counts compare source-line sets, not LLM billing. Boilerplate and unchanged processing are omitted when they contribute no required fact. The excerpt need not be a standalone compilable program; omitted closing delimiters are not evidence for additional behavior.
