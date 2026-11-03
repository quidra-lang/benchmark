# Task B selection: 24_word_stats / Quidra

## Common answer requirements

1. Locate both extreme-word decisions whose tie rule must change to last occurrence.
2. Preserve the original sentence, count, mean and four-line presentation.

## Implementation decision

Use an explicitly natural total for the sum of word lengths. len returns nat, so total += len(word) removes an unnecessary int conversion for every word while preserving the same exact mean and extreme-word scan.

## Evidence and answer

The greater-than and less-than comparisons and their assignments identify both update sites. In the existing forward scan, allow equality in each comparison so a later equal-length word replaces the earlier selection. Each assignment is needed to show which candidate becomes the selected word. Unchanged input, total/average calculation and output sites add no required modification fact.

## Selection and minimization

Selected complete main.qui lines: 7, 8, 9, 10. Every selected line is copied verbatim, once per source location and in source order. The excerpt is not required to compile independently. The stated Task B assumptions, language guarantees and documented first-party library semantics apply. The full source or contiguous context span is a larger alternative; unchanged unrelated input, processing and formatting are omitted when they supply no answer requirement. This is a reviewed minimum among the identified alternatives, not a proof of a global mathematical optimum.

Using unchanged metric/tokenizer.py: Task A 211 → 208; Task B 46 → 46. Compiler and native-output validation is recorded separately; token or verbatim checks alone do not establish compilation or correctness.
