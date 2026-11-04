# Task B selection: 14_moving_average / Quidra

## Common answer requirements

1. Locate the first window index and the inclusive three-element slice whose width must become five.
2. Retain ordered day labels, real averaging and two-decimal output.

## Implementation decision

Use a natural index directly against the natural length returned by len. The existing index starts at two and advances positively; changing its explicit type from int to nat removes the redundant conversion of the collection length without changing its slice or day labels.

## Evidence and answer

The range start and inclusive slice endpoints identify the two width-dependent sites: start at index four and extend the lower slice offset to four for a five-day window. math.mean supplies real division for the integer slice. import math binds this extension. The unchanged sales literal and output formatter supply no additional modification site.

## Selection and minimization

Selected complete main.qui lines: 1, 4, 5. Every selected line is copied verbatim, once per source location and in source order. The excerpt is not required to compile independently. The stated Task B assumptions, language guarantees and documented first-party library semantics apply. The full source or contiguous context span is a larger alternative; unchanged unrelated input, processing and formatting are omitted when they supply no answer requirement. This is a reviewed minimum among the identified alternatives, not a proof of a global mathematical optimum.

Using unchanged metric/tokenizer.py: Task A 129 → 118; Task B 45 → 39. Compiler and native-output validation is recorded separately; token or verbatim checks alone do not establish compilation or correctness.

Measurement: Task A 118; Task B 39. Tokenizer: metric/tokenizer.py, unchanged.
