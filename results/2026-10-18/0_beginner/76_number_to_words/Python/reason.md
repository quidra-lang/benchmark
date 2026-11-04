# Task B selection: 76_number_to_words / Python

## Common answer requirements

Trace 0, 71000 and 300019, including skipped zero remainders and separators.

## Supported analysis

The complete zero input emits zero through an explicit guard or an empty-parts fallback. In 71000 the quotient 71 yields seventy-one and remainder 0 is skipped: seventy-one thousand. In 300019 quotient 300 yields three hundred with no smaller remainder separator, and 19 gives nineteen: three hundred thousand nineteen. Join only nonempty components or insert a separator only when both neighboring components exist.

The excerpt is copied verbatim from `main.py`, in source order. Retained source lines: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 34, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 53, 54, 55, 56, 57, 58. Additional evidence is on line 22: `]`; line 34: `]`.

## Minimization and alternatives

The small lookup needs entries through nineteen and the tens lookup needs entries through seventy. Trailing tens entries are unnecessary unless a complete source line also contains a required entry. Retain table delimiters and the join/append operations. The prior selection used 473 tokens; this selection uses 465 tokens. Task A is assumed to satisfy its requirements for this analysis, as specified in README §2.3.
