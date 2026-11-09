# Task B selection — Swift

## Answer requirements shared across languages

1. Recognize CONVERT with source HEPBURN, target NIHON and text ji.
2. Trace the input-spelling lookup and equal-spelling tie resolution to the mora value and its source column.
3. Trace target spelling lookup and rendering to the final result zi under the initial case setting.

## Selected source locations

- `main.swift`: 10, 11, 12, 44, 48, 49, 54, 55, 56, 57, 58, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 103, 104, 111, 112, 119, 120, 145, 146, 147, 148, 149, 150, 155, 156, 172, 174, 184, 187, 188, 192, 193, 194, 195, 196, 197, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 218, 220, 221, 222, 249, 250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260, 261, 262, 263, 264, 276, 277, 278, 279, 280, 281, 282, 283, 284, 288, 289, 304, 307, 308, 309, 310, 311, 312, 315, 316, 325, 326, 342, 344, 347, 348, 349, 350, 353, 356, 480, 481, 523, 524, 528, 529, 530, 531, 532, 533, 534, 558, 562, 563, 567, 573, 574, 575, 576, 580, 581, 582, 583, 584, 585, 586, 587, 595, 596, 597, 598, 599

## Evidence and language semantics

CONVERT splits two arguments and systems recognizes HEPBURN and NIHON. The ordered Meta array inserts zi before di. HEPBURN maps both to ji; readers stores a spelling only when absent, preserving zi. match chooses the longest substring, returning SyllableMatch(zi,2), and parse constructs Mora(id:zi,column:1). NIHON returns the identity spelling. The sole regular non-L mora has false long flags, renders zi and retains pattern 0 under initial CASE KEEP; the final string is zi.

## Minimization and alternatives

The array order and nil-only reader insertion resolve the duplicate spelling; Swift Dictionary iteration is not used as an ordering assumption. slice is custom and retained to establish its substring semantics. Only ji matching, ordinary target rendering and final concatenation are selected; other commands, unmatched alternatives and long-vowel bodies are unnecessary.

The excerpt contains 2875 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
