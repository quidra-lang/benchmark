# Task B selection: 14_moving_average / Quidra

## Common answer requirements

1. Locate the first window index and the inclusive three-element slice whose width must become five.
2. Retain ordered day labels, real averaging and two-decimal output.

## Implementation decision

Use a natural index directly against the natural length returned by len. The index starts at two and advances positively; its bound len(sales) determines nat, removing the need for a repeated range type or a conversion of the length while preserving its slice and day labels.

## Evidence and answer

The range start and inclusive slice endpoints identify the two width-dependent sites: start at index four and extend the lower slice offset to four for a five-day window. math.mean supplies real division for the integer slice. import math binds this extension. The unchanged sales literal and output formatter supply no additional modification site.

## Selection and minimization

Selected complete main.qui lines: 1, 4, 5. Every selected line is copied verbatim, once per source location and in source order. The excerpt is not required to compile independently. The stated Task B assumptions, language guarantees and documented first-party library semantics apply. The full source or contiguous context span is a larger alternative; unchanged unrelated input, processing and formatting are omitted when they supply no answer requirement. This is a reviewed minimum among the identified alternatives, not a proof of a global mathematical optimum.

Using unchanged metric/tokenizer.py: Task A 129 → 115; Task B 45 → 38. Token or verbatim checks alone do not establish compilation or correctness.

Measurement: Task A 115; Task B 38. Tokenizer: metric/tokenizer.py, unchanged.
