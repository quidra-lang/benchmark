# Task B selection — Lua

## Answer requirements shared across languages

1. Recognize CONVERT with source HEPBURN, target NIHON and text ji.
2. Trace the input-spelling lookup and equal-spelling tie resolution to the mora value and its source column.
3. Trace target spelling lookup and rendering to the final result zi under the initial case setting.

## Selected source locations

- `main.lua`: 1, 2, 3, 4, 5, 6, 9, 10, 11, 13, 19, 24, 25, 26, 27, 28, 44, 45, 46, 47, 48, 49, 50, 61, 62, 69, 70, 71, 72, 73, 74, 75, 76, 77, 86, 90, 93, 94, 95, 96, 97, 100, 101, 102, 103, 104, 105, 109, 110, 111, 112, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 127, 128, 129, 130, 131, 132, 133, 134, 135, 140, 142, 143, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 194, 197, 198, 199, 200, 204, 205, 218, 219, 237, 239, 242, 243, 244, 255, 256, 257, 258, 259, 260, 261, 262, 264, 267, 275, 276, 277, 278, 279, 283, 284, 285, 286, 287, 290, 291, 292, 293, 294, 295, 296, 297, 298, 299, 409, 410, 413, 414, 423, 427, 428, 429, 430, 431, 432, 433, 434, 435, 436, 437, 438, 439, 440, 441, 442, 443, 477, 499, 500, 528, 529, 530, 532, 534, 535, 538, 539, 540, 541, 542, 543, 550, 551, 552, 553, 775

## Evidence and language semantics

CONVERT has two arguments validated as HEPBURN and NIHON. ipairs preserves the source row order zi before di. Both map to ji for HEPBURN; a seen table prevents a second entry, so zi survives independent of table.sort tie stability. match_syllable scans decreasing spelling length and parse_word records ids={zi}, columns={1}, advancing two. NIHON returns the identity spelling. The sole nonlong ordinary mora renders zi; CASE KEEP retains LOWER and replace_words concatenates exactly zi.

## Minimization and alternatives

Only ordered row construction, first-seen reading creation, the successful ji route, ordinary spelling and lowercase/default result path are retained. Custom split_words/contains helpers are needed for their actual recognition semantics. Other command cases, contracted spellings and special parse/render bodies are excluded; the length-sort does not decide the already-removed duplicate tie.

The excerpt contains 2823 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
