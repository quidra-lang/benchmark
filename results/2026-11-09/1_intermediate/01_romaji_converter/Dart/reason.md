# Task B selection — Dart

## Answer requirements shared across languages

1. Recognize CONVERT with source HEPBURN, target NIHON and text ji.
2. Trace the input-spelling lookup and equal-spelling tie resolution to the mora value and its source column.
3. Trace target spelling lookup and rendering to the final result zi under the initial case setting.

## Selected source locations

- `main.dart`: 3, 7, 10, 11, 15, 22, 23, 24, 26, 27, 28, 29, 32, 33, 34, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 71, 72, 73, 81, 82, 83, 84, 85, 88, 91, 92, 94, 95, 97, 98, 99, 108, 111, 112, 113, 114, 119, 120, 121, 122, 123, 124, 127, 128, 129, 130, 131, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 157, 158, 159, 160, 161, 162, 163, 170, 171, 172, 173, 174, 175, 176, 217, 221, 222, 223, 224, 236, 238, 239, 240, 241, 242, 243, 244, 245, 246, 250, 252, 253, 254, 255, 258, 267, 268, 287, 290, 291, 292, 293, 387, 388, 389, 390, 391, 392, 393, 394, 395, 396, 404, 405, 406, 409, 410, 411, 412, 413, 414, 415, 416, 418, 419, 420, 421, 422, 423, 424, 425, 426, 427, 459, 466, 467, 484, 485, 486, 487, 488, 489, 490, 491, 492, 493, 497, 498, 500, 501

## Evidence and language semantics

CONVERT takes two arguments and system lookup yields HEPBURN=0, NIHON=3. The ordered row table places zi before di. spelling maps both IDs to ji for HEPBURN, while NIHON returns the ID. match iterates IDs in order and changes best only for a strictly longer candidate, preserving zi on the equal-length tie. parse constructs Mora(zi,1) and consumes two letters. A sole non-L mora has no long element and parts emits zi; initial KEEP and lowercase pattern 0 leave the final StringBuffer result zi.

## Minimization and alternatives

The row order and strict length test are indispensable to resolve ji. Native list, string and StringBuffer behavior is sufficient; custom word splitting, case check, matching and parts are retained along the actual call chain. Only single ordinary-mora guards are required from long handling. Other commands and nonmatching parsing/rendering branches are excluded.

The excerpt contains 3208 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
