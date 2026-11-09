# Task B selection — Quidra

## Answer requirements shared across languages

1. Recognize CONVERT with source HEPBURN, target NIHON and text ji.
2. Trace the input-spelling lookup and equal-spelling tie resolution to the mora value and its source column.
3. Trace target spelling lookup and rendering to the final result zi under the initial case setting.

## Selected source locations

- `main.qui`: 1, 2, 3, 4, 5, 7, 8, 10, 11, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 37, 38, 40, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 73, 80, 92, 93, 94, 95, 96, 97, 98, 99, 102, 104, 105, 106, 107, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 135, 136, 137, 138, 139, 140, 141, 142, 143, 148, 149, 150, 151, 152, 153, 154, 159, 163, 165, 166, 167, 168, 169, 188, 189, 190, 191, 193, 194, 195, 196, 197, 198, 199, 200, 201, 210, 211, 213, 214, 215, 216, 217, 218, 223, 234, 235, 250, 251, 253, 254, 255, 256, 257, 258, 259, 260, 261, 262, 263, 264, 265, 339, 340, 341, 342, 343, 344, 359, 362, 363, 364, 365, 366, 367, 368, 369, 370, 371, 372, 373, 381, 382, 383, 384, 404, 408, 409, 410, 411, 412, 413, 414, 415, 416, 417, 418, 458, 459, 460, 461, 462, 463, 464, 467, 468, 469, 470, 471, 472, 473, 480, 481, 482, 483, 484, 485, 639, 640

## Evidence and language semantics

CONVERT reads two system arguments HEPBURN and NIHON, then text ji. inventory orders zi before di and HEPBURN spells both ji; the map insertion guard keeps the first system:spelling entry, zi. syllable tries widths 3,2,1 and returns Syllable(zi,2). read_word records morae=[zi], columns=[1]. NIHON preserves the original identifier, and a sole regular mora has no long flag; write_parts yields zi. Initial KEEP uses lowercase pattern 0, and execute returns exactly zi.

## Minimization and alternatives

Map.get/set/has, slices and joins use Quidra semantics. The custom locate, lower_ascii and contains bodies are retained where the successful route depends on them. Ordered data and absent-only insertion prove tie priority. Contracted spellings and failed parsing/rendering branches are excluded; guards establish that their bodies cannot affect this one-mora case.

The excerpt contains 3199 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
