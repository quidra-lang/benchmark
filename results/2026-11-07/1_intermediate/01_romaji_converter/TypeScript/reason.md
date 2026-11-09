# Task B selection — TypeScript

## Answer requirements shared across languages

1. Recognize CONVERT with source HEPBURN, target NIHON and text ji.
2. Trace the input-spelling lookup and equal-spelling tie resolution to the mora value and its source column.
3. Trace target spelling lookup and rendering to the final result zi under the initial case setting.

## Selected source locations

- `main.ts`: 13, 15, 19, 20, 23, 24, 25, 26, 27, 28, 29, 49, 50, 51, 61, 64, 65, 67, 68, 69, 83, 84, 85, 86, 87, 88, 89, 90, 91, 95, 96, 97, 100, 101, 104, 105, 106, 118, 119, 120, 121, 125, 126, 127, 128, 129, 130, 132, 133, 134, 135, 140, 142, 143, 144, 145, 146, 171, 172, 174, 177, 178, 179, 180, 181, 182, 185, 186, 201, 204, 205, 206, 207, 208, 212, 213, 224, 225, 243, 245, 248, 249, 250, 251, 254, 257, 260, 261, 262, 377, 378, 379, 385, 386, 389, 390, 391, 401, 402, 403, 404, 408, 409, 411, 413, 415, 416, 417, 418, 422, 457, 486, 487, 488, 490, 491, 492, 493, 494, 499, 500, 501

## Evidence and language semantics

CONVERT is recognized with two system arguments, HEPBURN and NIHON. rowData appends zi before di; HEPBURN spelling assigns ji to both. The entries Map inserts only absent spellings, retaining zi, and the lexicon is sorted by decreasing spelling length. matchAt finds ji and parseWord constructs {id:zi,column:1}, consuming both characters. NIHON spelling directly returns the ID zi. A single ordinary mora has no long element; initial CASE KEEP uses its LOWER pattern, and replaceWords returns zi.

## Minimization and alternatives

The ordered input rows, absent-only Map insertion and actual match/parse calls establish tie resolution and mora construction. Native Map, stable array sort, find, regex replacement and string operations supply their documented semantics. Only the single ordinary-mora branch and default lowercase route are retained; contracted spellings, failed matches, special mora rendering and other commands are unnecessary. The complete TypeScript lines retain their own annotations rather than borrowing JavaScript text.

The excerpt contains 2504 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
