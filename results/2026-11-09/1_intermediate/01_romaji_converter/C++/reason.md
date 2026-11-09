# Task B selection — C++

## Answer requirements shared across languages

1. Recognize CONVERT with source HEPBURN, target NIHON and text ji.
2. Trace the input-spelling lookup and equal-spelling tie resolution to the mora value and its source column.
3. Trace target spelling lookup and rendering to the final result zi under the initial case setting.

## Selected source locations

- `main.cpp`: 24, 27, 28, 30, 32, 33, 35, 36, 37, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 68, 69, 70, 71, 72, 73, 74, 76, 77, 78, 88, 89, 92, 93, 94, 95, 96, 98, 102, 108, 116, 117, 118, 119, 120, 125, 126, 127, 128, 129, 131, 132, 134, 135, 136, 137, 138, 142, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 170, 172, 173, 174, 175, 176, 194, 195, 196, 197, 198, 199, 200, 212, 214, 215, 216, 217, 218, 223, 225, 226, 227, 228, 229, 234, 240, 250, 252, 254, 255, 256, 257, 258, 259, 338, 339, 340, 341, 342, 343, 344, 345, 346, 351, 352, 353, 354, 355, 356, 357, 358, 359, 372, 373, 374, 375, 376, 377, 378, 379, 393, 400, 413, 414, 415, 416, 417, 418, 419, 424, 425, 426, 427, 428

## Evidence and language semantics

CONVERT is name index 2, takes two arguments and resolves HEPBURN=0, NIHON=3. initialize appends the za row before da, and both zi and di map to ji for HEPBURN. match updates only for a strictly longer spelling, retaining zi on the length-2 tie. parse constructs a token with that mora index and column 1. NIHON keeps the identity spelling zi. Single-token pair/long flags remain false, so parts selects the ordinary table spelling; default caseMode=0 and lowercase pattern=0 leave the assembled text zi.

## Minimization and alternatives

The strict match comparison and ordered table data are essential; neither a single replacement table entry nor the match call alone resolves the tie. The retained split/join/lower helpers establish actual custom behavior. Only the successful ji parsing, nonlong ordinary rendering, CONVERT target and final assembly are selected; reversed-word and special-mora bodies are unnecessary.

The excerpt contains 3672 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
