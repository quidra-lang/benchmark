# Task B selection — J

## Answer requirements shared across languages

1. Recognize CONVERT with source HEPBURN, target NIHON and text ji.
2. Trace the input-spelling lookup and equal-spelling tie resolution to the mora value and its source column.
3. Trace target spelling lookup and rendering to the final result zi under the initial case setting.

## Selected source locations

- `main.ijs`: 1, 2, 8, 9, 24, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 70, 84, 86, 90, 91, 92, 93, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 123, 124, 125, 126, 127, 128, 129, 130, 143, 144, 145, 146, 147, 173, 174, 175, 176, 177, 179, 180, 181, 182, 183, 184, 185, 186, 201, 203, 205, 206, 207, 208, 209, 210, 211, 212, 221, 232, 233, 250, 252, 254, 255, 256, 257, 258, 259, 260, 261, 262, 340, 341, 342, 343, 344, 345, 360, 361, 362, 363, 367, 368, 369, 370, 371, 372, 373, 374, 375, 376, 383, 384, 385, 406, 409, 410, 411, 412, 413, 414, 415, 416, 417, 418, 419, 420, 421, 422, 461, 462, 463, 464, 465, 466, 467, 468, 469, 472, 473, 474, 475, 476, 477, 478, 479, 480, 491, 493, 494, 496

## Evidence and language semantics

CONVERT is recognized with argc=2 and source/target positions resolve to HEPBURN=0 and NIHON=3. initialize appends ordered IDs with zi before di and assigns both the spelling ji in HEPBURN; NIHON keeps identifier. syllable scans IDs in order and updates only when size>width, retaining zi on equal length. read_word stores mora zi and source column 1 and consumes two characters. The one ordinary non-L mora has zero long flags, so write_parts uses the NIHON zi entry. KEEP plus lowercase pattern 0 preserves zi, and execute returns it with the untouched empty suffix.

## Minimization and alternatives

J array/boxed indexing and explicit loop order supply the priority, without relying on map order. Ordered groups, spelling construction and strict width comparison are retained. The custom text_equal and split verbs are needed; join is not called on this CONVERT route. Other commands, special mora parsing and skipped long-pair bodies are excluded.

The excerpt contains 2374 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
