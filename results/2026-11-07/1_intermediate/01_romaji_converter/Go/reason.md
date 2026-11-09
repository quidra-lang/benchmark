# Task B selection — Go

## Answer requirements shared across languages

1. Recognize CONVERT with source HEPBURN, target NIHON and text ji.
2. Trace the input-spelling lookup and equal-spelling tie resolution to the mora value and its source column.
3. Trace target spelling lookup and rendering to the final result zi under the initial case setting.

## Selected source locations

- `main.go`: 14, 16, 31, 33, 37, 39, 40, 41, 42, 54, 55, 56, 57, 58, 59, 60, 62, 63, 67, 78, 79, 82, 83, 84, 85, 86, 87, 89, 90, 99, 105, 106, 107, 108, 109, 114, 115, 116, 117, 118, 120, 121, 124, 125, 126, 127, 128, 132, 133, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 163, 165, 166, 167, 168, 169, 190, 191, 192, 193, 194, 195, 196, 197, 209, 210, 211, 212, 213, 214, 216, 217, 218, 219, 227, 228, 239, 240, 254, 256, 258, 259, 260, 261, 262, 263, 264, 265, 266, 267, 359, 360, 361, 362, 363, 364, 365, 366, 371, 372, 373, 374, 375, 376, 377, 378, 379, 394, 395, 396, 397, 398, 399, 400, 401, 402, 419, 431, 451, 452, 454, 456, 457, 458, 459, 460, 461, 462, 463, 464, 472, 473, 474, 475, 476, 477, 660

## Evidence and language semantics

The command table resolves CONVERT=2 and the two system arguments resolve HEPBURN=0, NIHON=3 by slices.Index. initialize appends zi before di and assigns ji to both at system 0. match scans in that order and updates only for strictly longer spellings, so the two-letter tie retains zi. parse creates token{id,1} and consumes two characters. At target 3, identity spelling zi is used; a sole ordinary token has no long flag. Zero-valued settings{} and lowercase pattern 0 keep the output lowercase; strings.Builder assembles exactly zi.

## Minimization and alternatives

Standard strings/slices operations need no implementations. Only custom lex, case, match, parse and parts/write dependencies on this route are retained. The absent pair loop for one token and explicit non-L guard suffice instead of full long-vowel logic. Other commands and special-mora alternatives cannot affect this valid ji scenario.

The excerpt contains 2991 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
