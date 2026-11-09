# Task B selection — JavaScript

## Answer requirements shared across languages

1. Recognize CONVERT with source HEPBURN, target NIHON and text ji.
2. Trace the input-spelling lookup and equal-spelling tie resolution to the mora value and its source column.
3. Trace target spelling lookup and rendering to the final result zi under the initial case setting.

## Selected source locations

- `main.js`: 6, 8, 12, 13, 16, 17, 18, 19, 20, 21, 22, 42, 43, 44, 54, 57, 58, 60, 61, 62, 76, 77, 78, 79, 80, 81, 82, 83, 84, 88, 89, 90, 93, 94, 97, 98, 99, 111, 112, 113, 114, 118, 119, 120, 121, 122, 123, 125, 126, 127, 128, 133, 135, 136, 137, 138, 139, 164, 165, 167, 170, 171, 172, 173, 174, 175, 178, 179, 194, 197, 198, 199, 200, 201, 205, 206, 217, 218, 236, 238, 241, 242, 243, 244, 247, 250, 253, 254, 255, 370, 371, 372, 378, 379, 382, 383, 384, 394, 395, 396, 397, 401, 402, 404, 406, 408, 409, 410, 411, 415, 450, 479, 480, 481, 483, 484, 485, 486, 487, 492, 493, 494

## Evidence and language semantics

CONVERT is recognized with two system arguments, HEPBURN and NIHON. rowData appends zi before di; HEPBURN spelling assigns ji to both. The entries Map inserts only absent spellings, retaining zi, and the lexicon is sorted by decreasing spelling length. matchAt finds ji and parseWord constructs {id:zi,column:1}, consuming both characters. NIHON spelling directly returns the ID zi. A single ordinary mora has no long element; initial CASE KEEP uses its LOWER pattern, and replaceWords returns zi.

## Minimization and alternatives

The ordered input rows, absent-only Map insertion and actual match/parse calls establish tie resolution and mora construction. Native Map, stable array sort, find, regex replacement and string operations supply their documented semantics. Only the single ordinary-mora branch and default lowercase route are retained; contracted spellings, failed matches, special mora rendering and other commands are unnecessary. The complete TypeScript lines retain their own annotations rather than borrowing JavaScript text.

The excerpt contains 2327 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
