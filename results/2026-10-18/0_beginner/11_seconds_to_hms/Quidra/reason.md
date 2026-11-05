# Task B selection: 11_seconds_to_hms / Quidra

## Common answer requirements

1. Trace the question-supplied duration 312047 seconds into elapsed hours, minutes and seconds.
2. Explain division and remainders, why hours are not reduced to a day, and two-digit minute/second presentation.

## Source evidence and minimization

Line 2 of `main.qui` contains all three integer calculations and the output format.
For `312047`, integer division by `3600` gives 86 elapsed hours, with no
24-hour reduction. Dividing by `60` gives 5200 whole minutes. Taking that
result modulo `60` gives 40 minutes, and `312047 % 60` gives 47 seconds.
Both remainders are in the range 0 through 59. The `:02.` fields zero-pad the
components to two digits, yielding `312047 seconds = 86:40:47`.

The question supplies the integer duration, so the loop header only adds
the other inputs and their order. The output line alone answers the question
and is copied verbatim into the excerpt.

The repository tokenizer counts 101 tokens for Task A and 58 for Task B.
