# Task B selection — PHP

## Answer requirements shared across languages

1. Recognize CONVERT with source HEPBURN, target NIHON and text ji.
2. Trace the input-spelling lookup and equal-spelling tie resolution to the mora value and its source column.
3. Trace target spelling lookup and rendering to the final result zi under the initial case setting.

## Selected source locations

- `main.php`: 2, 3, 4, 6, 12, 18, 19, 22, 23, 24, 25, 51, 53, 54, 62, 64, 65, 66, 67, 68, 69, 70, 81, 86, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 109, 111, 112, 115, 118, 120, 121, 122, 123, 124, 125, 128, 129, 130, 135, 137, 138, 139, 163, 164, 165, 166, 167, 170, 172, 173, 174, 175, 189, 192, 194, 195, 196, 200, 213, 214, 232, 234, 237, 239, 240, 251, 253, 254, 255, 256, 259, 262, 264, 265, 266, 267, 270, 273, 275, 276, 277, 278, 279, 280, 281, 282, 385, 386, 387, 388, 389, 390, 400, 404, 405, 406, 407, 408, 409, 410, 411, 412, 413, 414, 415, 416, 446, 467, 468, 497, 498, 502, 503, 504, 505, 507, 509, 510, 511, 512, 513, 514, 515, 523, 524, 525, 526, 722

## Evidence and language semantics

CONVERT parses two system arguments HEPBURN/NIHON and text ji. Ordered identifiers put zi before di. HEPBURN maps both to ji; the !isset guard preserves the first zi mapping before sorting lengths. array_find finds ji and parse_word records ids=[zi], columns=[1], consuming two bytes. NIHON falls through to its unchanged id. The single ordinary mora has no long flag; CASE KEEP uses LOWER and written plus replace_words produces zi.

## Minimization and alternatives

PHP ordered arrays and standard usort/array_find/string functions are used directly. The first-seen mapping guard is retained to prove zi wins; no ordering guarantee of an unrelated map is assumed. The excerpt excludes contracted IDs, failed-match alternatives, unrelated commands and skipped special rendering branches, while keeping actual reference assignment into words and final replacement.

The excerpt contains 3025 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
