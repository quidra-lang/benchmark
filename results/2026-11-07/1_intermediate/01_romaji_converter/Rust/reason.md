# Task B selection — Rust

## Answer requirements shared across languages

1. Recognize CONVERT with source HEPBURN, target NIHON and text ji.
2. Trace the input-spelling lookup and equal-spelling tie resolution to the mora value and its source column.
3. Trace target spelling lookup and rendering to the final result zi under the initial case setting.

## Selected source locations

- `main.rs`: 3, 5, 6, 27, 28, 30, 31, 34, 39, 40, 41, 42, 43, 44, 45, 47, 48, 49, 50, 51, 52, 66, 67, 70, 71, 72, 73, 74, 75, 76, 79, 88, 91, 93, 94, 95, 96, 97, 98, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 148, 149, 150, 174, 175, 176, 177, 178, 179, 180, 181, 182, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 209, 210, 219, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 314, 315, 316, 317, 318, 319, 320, 326, 327, 328, 329, 330, 331, 332, 333, 346, 347, 348, 349, 350, 351, 362, 369, 391, 392, 393, 394, 395, 396, 397, 398, 399, 400, 401, 409, 410, 411, 412, 413, 414, 561

## Evidence and language semantics

The command table resolves CONVERT=2 with two systems, and index resolves HEPBURN=0 and NIHON=3. Ordered row construction places zi before di; both source spellings are ji. match_mora updates only on strictly greater length, so the length-2 match retains the earlier zi index. parse constructs Token{id,col:1} and advances by two. NIHON keeps identity spelling zi. The sole ordinary token is not a long element; default Settings fields are zero and lowercase pattern 0 avoids case changes. The returned Ok string is zi.

## Minimization and alternatives

Rust Option/Result propagation, slice positions, vector order and derived Default semantics are used directly. The selected custom helper bodies are necessary for matching/tie behavior and rendering. Other failed-match branches, reverse handling and full long-pair calculations are excluded; the one-token loop guards and non-L test establish the applicable regular path.

The excerpt contains 3259 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
