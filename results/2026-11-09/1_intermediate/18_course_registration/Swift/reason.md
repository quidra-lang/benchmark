# Task B selection — Swift

## Answer requirements shared across languages

1. Identify the registered-course credit value and its construction, separately from capacity and grade-record credits.
2. Explain how to admit whole course credits 1..8 while retaining the separate grade-record digit contract 1..6; distinguish represented whole values from a statically enforced range.

## Selected source locations

- `main.swift`: 223, 250, 412, 429, 437

## Evidence and language semantics

Course has Int credits initialized from Int(a[1]); a grade tuple has its own Int credits derived from pieces[2]. The course construction shown has no 1..6 range restriction in its numeric conversion, so valid new inputs 7 and 8 are already representable; widening the accepted COURSE input contract needs no fractional representation or wider numeric storage. Keep the distinct grade-record path and its 1..6 input contract unchanged. These excerpts do not claim either input bound is statically enforced.

## Minimization and alternatives

The two credit constructions are the affected boundary and the separate boundary that must stay unchanged. Their integer conversions/types suffice; capacity, prerequisite evaluation, enrollment sums, GPA, and output consumers do not need changes. A storage declaration alone would hide which token initializes each credit value; whole constructors/handlers add unrelated fields.

The excerpt contains 128 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
