# Task B selection: 08_leap_years / R

## Common answer requirements

1. Locate the year collection and any traversal extent that must grow from eight to nine.
2. Append 2400 after 2100 without changing the original order, leap predicate, or output formatting.

## Answer supported by the excerpt

Append 2400 at the end of the selected ordered collection. Increase an explicitly fixed array size or traversal bound from eight to nine when present. Element-based iteration otherwise visits the added ninth entry automatically. Keep the existing leap-year and output body unchanged; no separate new-year branch or formatter is needed.

## Source evidence and dependencies

Selected `main.R` lines: 1. The excerpt preserves these complete lines in their original order and indentation.

The literal collection gives the insertion point after 2100 and preserves the preceding eight values. The loop header shows whether traversal uses a hardcoded length or the collection itself. The C++ array extent is on the same retained declaration. Existing leap classification and presentation are unaffected by adding an input entry.

## Language semantics and minimization

Use the language's ordinary evaluation, indexing, iteration and numeric semantics, and the documented behavior of the standard-library operations visible in the excerpt. The Task B assumptions apply; this is not a build or correctness verification. Selecting only the array could miss a hardcoded traversal bound; selecting only the loop would not identify where to append the year. Where the literal collection and traversal share one line, that line alone is sufficient. Copying the unchanged Gregorian predicate or format adds no modification site.

The selected excerpt contains **60 tokens** under `metric/tokenizer.py`. The contiguous source span from its first through last selected line contains 60 tokens; the complete source contains 150 tokens. These counts compare source-line sets, not LLM billing. Boilerplate and unchanged processing are omitted when they contribute no required fact. The excerpt need not be a standalone compilable program; omitted closing delimiters are not evidence for additional behavior.
