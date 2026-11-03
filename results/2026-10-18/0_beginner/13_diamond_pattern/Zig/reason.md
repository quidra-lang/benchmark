# Task B selection: 13_diamond_pattern / Zig

## Common answer requirements

1. Derive spaces and stars for printed lines five and six of the size-five diamond.
2. Explain the transition from expansion to shrinkage and why the widest row is printed once.

## Answer supported by the excerpt

The fifth printed row has effective size i=5: n-i=0 spaces and 2i-1=9 stars. The sixth has i=4: one leading space and seven stars. A one-based row loop changes from row to 2n-row after row5; a zero-based loop changes after row4. In two-range implementations, the decreasing range starts at n-1, not n, so the widest row is not repeated.

## Source evidence and dependencies

Selected `main.zig` lines: 5-12. The excerpt preserves these complete lines in their original order and indentation.

The size, row enumeration, effective-size formula and character repetition/output jointly determine the two requested rows. The enumeration distinguishes zero-based and one-based cases and shows whether the widest level can repeat. A separately named row helper requires its body because the name does not establish spaces or star counts.

The writer construction identifies standard splatByteAll and writeByte semantics; row starts at zero, so the fifth/sixth iterations are row4/row5.

## Language semantics and minimization

Use the language's ordinary evaluation, indexing, iteration and numeric semantics, and the documented behavior of the standard-library operations visible in the excerpt. The Task B assumptions apply; this is not a build or correctness verification. The output formula without enumeration cannot identify which effective size belongs to printed lines five and six. The bounds without the output formula cannot determine their characters. Their selected union is sufficient, while the wrapper and imports add no diamond-specific fact.

The selected excerpt contains **188 tokens** under `metric/tokenizer.py`. The contiguous source span from its first through last selected line contains 188 tokens; the complete source contains 261 tokens. These counts compare source-line sets, not LLM billing. Boilerplate and unchanged processing are omitted when they contribute no required fact. The excerpt need not be a standalone compilable program; omitted closing delimiters are not evidence for additional behavior.
