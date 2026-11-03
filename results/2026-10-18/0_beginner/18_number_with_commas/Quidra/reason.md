# Task B selection: 18_number_with_commas / Quidra

## Common answer requirements

1. For the question-supplied integer -456789, derive the comma-grouped output and newline.
2. Explain grouping digits from the right, with the minus sign outside those groups.

## Implementation decision

Task A remains unchanged. Omit the unrelated literal array from Task B while retaining the explicit integer item binder and the formatter.

## Evidence and answer

The loop header supplies the current variable and its int type. With the question-supplied value -456789, Core group=3 formatting groups the magnitude digits from the right as 456 and 789, then retains the leading minus sign outside those groups. print.line yields -456,789 followed by a newline. Core numeric-format semantics guarantee that no comma follows the sign. The other input numbers do not supply another required fact. Python retains its original loop line because that complete line also provides its input binding/type evidence; this follows the same requirement rather than forcing identical line counts.

## Selection and minimization

Selected complete main.qui lines: 2, 3. Every selected line is copied verbatim, once per source location and in source order. The excerpt is not required to compile independently. The stated Task B assumptions, language guarantees and documented first-party library semantics apply. The full source or contiguous context span is a larger alternative; unchanged unrelated input, processing and formatting are omitted when they supply no answer requirement. This is a reviewed minimum among the identified alternatives, not a proof of a global mathematical optimum.

Using unchanged metric/tokenizer.py: Task A 82 → 82; Task B 82 → 27. Compiler and native-output validation is recorded separately; token or verbatim checks alone do not establish compilation or correctness.
