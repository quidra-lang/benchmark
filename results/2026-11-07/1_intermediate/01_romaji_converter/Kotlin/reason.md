# Task B selection — Kotlin

## Answer requirements shared across languages

1. Recognize CONVERT with source HEPBURN, target NIHON and text ji.
2. Trace the input-spelling lookup and equal-spelling tie resolution to the mora value and its source column.
3. Trace target spelling lookup and rendering to the final result zi under the initial case setting.

## Selected source locations

- `main.kt`: 3, 4, 10, 14, 18, 19, 20, 21, 25, 26, 27, 28, 29, 30, 39, 40, 41, 42, 43, 44, 45, 52, 54, 68, 69, 70, 71, 76, 77, 93, 95, 105, 107, 108, 109, 110, 111, 112, 113, 114, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 133, 135, 136, 137, 138, 139, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 185, 186, 187, 188, 189, 190, 191, 195, 196, 211, 213, 214, 215, 216, 217, 220, 221, 230, 231, 243, 245, 247, 248, 249, 250, 251, 255, 258, 261, 366, 367, 403, 404, 408, 409, 410, 411, 412, 413, 435, 439, 440, 444, 449, 450, 451, 452, 456, 457, 458, 459, 460, 461, 462, 468, 469, 470, 471, 472, 473, 474, 475

## Evidence and language semantics

CONVERT consumes two system arguments; systems recognizes HEPBURN and NIHON. linkedMapOf metadata preserves the row order zi before di. HEPBURN maps both to ji and putIfAbsent retains the first zi. match descends substring lengths and returns MatchResult(zi,2), then parse builds Mora(zi,1). NIHON uses spelling's identity return. With one ordinary non-L mora long flags stay false, Parts yields zi, and default CASE KEEP plus pattern 0 preserves lowercase in the final StringBuilder result.

## Minimization and alternatives

The ordered table and first-insertion reader operation are needed to resolve ji rather than assuming the mapping is injective. Only the successful matched-mora route and ordinary write path are kept. Default settings, lowercase pattern and one-mora long guards support the result without the complete case/long-vowel algorithms.

The excerpt contains 2572 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
