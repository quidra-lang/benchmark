# Task B selection — Python

## Answer requirements shared across languages

1. Recognize CONVERT with source HEPBURN, target NIHON and text ji.
2. Trace the input-spelling lookup and equal-spelling tie resolution to the mora value and its source column.
3. Trace target spelling lookup and rendering to the final result zi under the initial case setting.

## Selected source locations

- `main.py`: 6, 8, 9, 10, 12, 13, 25, 26, 44, 47, 48, 49, 50, 51, 52, 53, 59, 62, 65, 66, 67, 68, 70, 71, 79, 82, 83, 84, 85, 86, 87, 88, 100, 101, 102, 103, 111, 112, 113, 114, 115, 116, 122, 123, 124, 125, 126, 127, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 147, 148, 149, 170, 171, 172, 175, 176, 177, 178, 188, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 204, 205, 207, 208, 209, 210, 211, 223, 224, 240, 241, 244, 245, 247, 249, 298, 336, 337, 338, 339, 340, 349, 352, 353, 354, 371, 374, 377, 383, 384, 385, 390, 392, 403, 404, 408, 409, 410, 411, 412, 413, 414, 415, 416, 434, 435

## Evidence and language semantics

FORMATS gives CONVERT two arguments and two system names; prepare_request splits the line and recognizes both systems. The insertion-ordered ROWS places za/zi before da/di. HEPBURN maps both zi and di to ji, and inverse.setdefault keeps the first identifier, zi. syllable_at tries lengths 3,2,1, so ji consumes two letters and constructs Mora(zi,1). NIHON retains the identity spelling table, yielding zi. A single ordinary mora has no long element. The initial CASE=KEEP preserves its lowercase pattern and rewrite_text substitutes zi into the sole word.

## Minimization and alternatives

Only the ji route through row construction, dictionary inversion, matching, mora creation and rendering is retained. Other rows, contracted spelling rewrites, special n/tsu/long-mark parse branches, other commands and error cases are excluded. The two conflicting rows and first-insertion semantics are essential; selecting only the zi=>ji mapping would not resolve the di tie. Long-pair guards and lowercase/default paths are retained so the excerpt alone establishes unmodified zi output.

The excerpt contains 2114 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
