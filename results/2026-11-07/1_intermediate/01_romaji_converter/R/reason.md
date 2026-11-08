# Task B selection — R

## Answer requirements shared across languages

1. Recognize CONVERT with source HEPBURN, target NIHON and text ji.
2. Trace the input-spelling lookup and equal-spelling tie resolution to the mora value and its source column.
3. Trace target spelling lookup and rendering to the final result zi under the initial case setting.

## Selected source locations

- `main.R`: 1, 2, 3, 4, 6, 12, 16, 17, 20, 21, 22, 23, 24, 42, 48, 50, 51, 52, 53, 54, 55, 56, 65, 69, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 92, 93, 94, 95, 96, 97, 98, 101, 102, 103, 108, 110, 111, 112, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 161, 164, 165, 166, 167, 168, 172, 185, 186, 204, 206, 209, 210, 217, 218, 219, 220, 221, 222, 223, 230, 231, 232, 233, 234, 235, 236, 238, 241, 242, 243, 244, 245, 246, 247, 248, 249, 343, 344, 345, 346, 352, 354, 355, 356, 357, 358, 359, 360, 361, 362, 364, 365, 366, 367, 368, 369, 370, 371, 395, 405, 406, 429, 430, 431, 435, 436, 437, 438, 439, 440, 443, 444, 445, 446, 447, 448, 454, 455, 456, 457, 619, 620, 621

## Evidence and language semantics

CONVERT recognizes two systems HEPBURN and NIHON. identifiers preserve source row order zi before di. Both map to ji in HEPBURN, and the named seen vector assigns only an absent spelling, retaining zi; decreasing-length ordering and first TRUE match select ji. parse_word returns ids=zi and columns=1, advancing two characters. NIHON keeps id unchanged. The sole ordinary mora is nonlong, CASE KEEP retains LOWER and written/replace_words yields zi.

## Minimization and alternatives

The ordered identifier vector and absent-only named-vector assignment establish tie resolution independently of unrelated ordering. Native vector indexing, order, match, string and formatting semantics need no helper implementations. The custom character and rewrite helpers are retained where used; the full special-mora, long-vowel and other-command logic is excluded.

The excerpt contains 2561 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
