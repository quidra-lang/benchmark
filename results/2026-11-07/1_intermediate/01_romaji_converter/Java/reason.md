# Task B selection — Java

## Answer requirements shared across languages

1. Recognize CONVERT with source HEPBURN, target NIHON and text ji.
2. Trace the input-spelling lookup and equal-spelling tie resolution to the mora value and its source column.
3. Trace target spelling lookup and rendering to the final result zi under the initial case setting.

## Selected source locations

- `Main.java`: 6, 7, 13, 23, 27, 28, 29, 30, 33, 34, 35, 36, 37, 38, 47, 48, 49, 50, 51, 52, 53, 54, 65, 66, 71, 72, 96, 97, 98, 99, 100, 105, 106, 122, 124, 134, 136, 137, 138, 139, 140, 141, 142, 143, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 161, 164, 165, 166, 167, 168, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 234, 235, 236, 237, 238, 239, 240, 244, 245, 259, 261, 262, 263, 264, 265, 266, 267, 270, 271, 280, 281, 300, 302, 304, 305, 306, 307, 310, 313, 424, 425, 471, 472, 476, 477, 478, 479, 480, 481, 482, 507, 511, 512, 513, 517, 522, 523, 524, 525, 526, 530, 531, 532, 533, 534, 535, 536, 537, 545, 546, 547, 548, 549, 550

## Evidence and language semantics

CONVERT has count 2 and two recognized system arguments. LinkedHashMap metadata preserves row insertion: za/zi precedes da/di. HEPBURN spelling maps both to ji, and putIfAbsent in readers preserves zi. match tries the longest available substrings and returns Match(zi,2); parse constructs Mora(zi,1). NIHON returns the identity id from spelling. A single non-L mora has false long flags; ordinary parts yields zi, initial CASE KEEP retains lowercase pattern 0, and the StringBuilder returns zi.

## Minimization and alternatives

Retain the ordered metadata declaration, conflicting rows and putIfAbsent; HashMap lookup alone cannot recover tie priority. The chosen route omits unrelated command validation and nonmatching special parse/render cases. Native map/list/regex/StringBuilder semantics need no implementation; custom spelling/scan/match/render paths are necessary.

The excerpt contains 3032 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
