# Task B selection — C#

## Answer requirements shared across languages

1. Recognize CONVERT with source HEPBURN, target NIHON and text ji.
2. Trace the input-spelling lookup and equal-spelling tie resolution to the mora value and its source column.
3. Trace target spelling lookup and rendering to the final result zi under the initial case setting.

## Selected source locations

- `Program.cs`: 10, 18, 22, 23, 28, 29, 30, 31, 34, 35, 36, 37, 38, 39, 48, 49, 52, 53, 54, 55, 60, 61, 62, 72, 82, 83, 84, 85, 86, 87, 100, 102, 108, 110, 111, 112, 113, 114, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 138, 139, 140, 141, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 195, 196, 198, 199, 200, 204, 205, 219, 221, 222, 223, 224, 225, 228, 229, 238, 239, 258, 260, 262, 263, 264, 265, 268, 271, 369, 410, 411, 415, 416, 417, 418, 419, 420, 445, 449, 450, 451, 452, 453, 454, 455, 459, 460, 461, 462, 466, 469, 470, 471, 472, 473, 474, 485, 486, 488, 489

## Evidence and language semantics

CONVERT takes two arguments; split/Systems checks recognize HEPBURN and NIHON. Table row insertion puts zi before di. Spelling maps both to ji in HEPBURN; Dictionary.TryAdd preserves the first, so Match returns zi with length 2. Parse constructs Mora(zi,1). NIHON takes Spelling's identity return, and Parts emits zi for that ordinary mora. The zero-initialized long flags have no pair or L on this one-mora word. CASE=KEEP plus lowercase Pattern=0 leaves the StringBuilder result zi.

## Minimization and alternatives

The selection follows the actual row table/readers, Parse and Write calls, not merely same-named helpers. Unrelated mora rows share complete data lines where unavoidable; other command branches, failed-match alternatives and nonmatching rendering branches are removed. Metadata insertion and Regular are included to justify ordinary-mora selection; the single-mora flag guards avoid including the full long-vowel algorithm.

The excerpt contains 2683 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
