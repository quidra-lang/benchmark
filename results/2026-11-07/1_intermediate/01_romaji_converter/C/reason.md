# Task B selection — C

## Answer requirements shared across languages

1. Recognize CONVERT with source HEPBURN, target NIHON and text ji.
2. Trace the input-spelling lookup and equal-spelling tie resolution to the mora value and its source column.
3. Trace target spelling lookup and rendering to the final result zi under the initial case setting.

## Selected source locations

- `main.c`: 9, 11, 29, 32, 36, 37, 38, 39, 48, 49, 52, 53, 54, 55, 56, 57, 83, 84, 85, 86, 87, 88, 89, 92, 93, 94, 95, 96, 97, 98, 99, 118, 119, 122, 123, 124, 125, 126, 127, 128, 139, 140, 141, 142, 147, 148, 149, 151, 152, 153, 154, 155, 157, 158, 161, 162, 163, 164, 165, 169, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 202, 203, 204, 205, 220, 221, 222, 223, 225, 226, 227, 239, 240, 243, 244, 245, 246, 247, 248, 249, 252, 262, 276, 277, 278, 279, 280, 281, 282, 283, 386, 387, 388, 389, 390, 391, 392, 393, 394, 403, 404, 405, 406, 407, 408, 409, 410, 411, 429, 430, 431, 432, 433, 434, 435, 449, 458, 482, 483, 485, 486, 487, 488, 489, 490, 491, 505, 506, 507, 508, 509, 510, 511

## Evidence and language semantics

The command-name/fixed-count tables resolve CONVERT to 2 and system lookup resolves HEPBURN=0, NIHON=3. Rows build zi before di; HEPBURN assigns ji to both. match scans mora IDs in order and only replaces a match for strictly greater spelling length, so zi wins the equal-length tie. parse stores its ID and source column 1, consumes two characters and produces one token. NIHON's initialized identity spelling is zi; parts selects this regular token with no long flag. Initial zero case_mode preserves lower-case pattern 0, and write_word/append return exactly zi.

## Minimization and alternatives

The two source rows, strict length comparison and target identity initialization are necessary; a call named match alone cannot establish tie behavior. Only the successful ji parse and regular-token rendering path are kept, plus the single-token long-flag guards. Other commands, contracted conversions, other parse alternatives and output formatting unrelated to this sole word are omitted.

The excerpt contains 3771 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
