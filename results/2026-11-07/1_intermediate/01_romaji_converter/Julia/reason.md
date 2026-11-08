# Task B selection — Julia

## Answer requirements shared across languages

1. Recognize CONVERT with source HEPBURN, target NIHON and text ji.
2. Trace the input-spelling lookup and equal-spelling tie resolution to the mora value and its source column.
3. Trace target spelling lookup and rendering to the final result zi under the initial case setting.

## Selected source locations

- `main.jl`: 1, 2, 4, 6, 12, 19, 20, 21, 24, 25, 26, 27, 41, 43, 44, 45, 49, 50, 51, 52, 53, 54, 55, 56, 64, 69, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 91, 94, 95, 96, 97, 100, 101, 102, 103, 104, 105, 106, 109, 110, 111, 114, 116, 117, 118, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 166, 169, 170, 171, 172, 173, 177, 190, 191, 209, 211, 214, 215, 216, 217, 218, 219, 224, 225, 235, 236, 237, 238, 239, 240, 241, 244, 245, 246, 247, 248, 249, 250, 251, 254, 255, 256, 257, 258, 259, 260, 261, 262, 346, 347, 348, 349, 355, 356, 357, 358, 359, 360, 361, 362, 363, 364, 365, 366, 367, 368, 369, 387, 395, 396, 420, 421, 425, 426, 427, 428, 431, 432, 433, 434, 435, 436, 437, 441, 442, 443, 444, 580

## Evidence and language semantics

CONVERT recognizes two system arguments HEPBURN and NIHON. Ordered IDS from ROW_TEXT place zi before di. HEPBURN spelling maps both to ji; reading_tables records only unseen spelling keys, retaining zi before sorting by length. match_syllable returns ji=>zi; parse_word records ids=[zi], columns=[1] and advances two characters. NIHON falls through to identity id. One ordinary mora has no long flag. Initial CASE KEEP uses LOWER, and written/replace_words returns zi.

## Minimization and alternatives

The IDS vector supplies priority independently of Dict iteration order; first-seen insertion resolves the only duplicated ji spelling before length ordering. The selected custom parsers and renderers establish the full path. One-mora loop guards replace unnecessary long-vowel bodies; unrelated settings changes, commands and special-mora branches are excluded.

The excerpt contains 2322 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
