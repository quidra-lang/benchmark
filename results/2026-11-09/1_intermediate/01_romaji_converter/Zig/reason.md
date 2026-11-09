# Task B selection — Zig

## Answer requirements shared across languages

1. Recognize CONVERT with source HEPBURN, target NIHON and text ji.
2. Trace the input-spelling lookup and equal-spelling tie resolution to the mora value and its source column.
3. Trace target spelling lookup and rendering to the final result zi under the initial case setting.

## Selected source locations

- `main.zig`: 5, 8, 20, 21, 26, 28, 29, 31, 35, 36, 37, 38, 39, 40, 41, 46, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 82, 83, 84, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 132, 133, 135, 136, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 165, 166, 167, 168, 173, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 251, 252, 253, 254, 255, 256, 257, 258, 266, 268, 269, 270, 271, 272, 311, 314, 315, 316, 317, 318, 332, 335, 336, 337, 338, 339, 340, 341, 342, 343, 344, 345, 350, 353, 354, 355, 356, 360, 369, 370, 389, 392, 393, 394, 395, 396, 397, 398, 399, 400, 518, 519, 520, 521, 522, 523, 524, 525, 526, 527, 528, 540, 541, 542, 543, 544, 545, 546, 547, 548, 549, 550, 551, 552, 553, 554, 555, 556, 557, 558, 559, 597, 612, 613, 639, 640, 641, 642, 643, 644, 645, 646, 647, 659, 660, 661, 662, 663, 664

## Evidence and language semantics

CONVERT takes two system arguments; choice resolves HEPBURN=0 and NIHON=3. init constructs table IDs in row order, zi before di. Both spell ji in HEPBURN; matchAt replaces best only for strictly longer candidate length, retaining the earlier zi. parse appends Mora{id:zi,column:1} and consumes two bytes. NIHON spelling returns zi; one ordinary non-L mora has false pair/long flags, so parts yields zi. Initial case_mode=0 and lowercase pattern=0 preserve zi; execute writes this and the empty surrounding slices.

## Minimization and alternatives

The ordered table and strict greater-length test resolve the duplicated ji spelling. Standard std.mem/std.ascii operations supply their documented meanings; custom choice, tokenization, case and rendering paths are retained. Only the applicable matched and ordinary-mora branches are selected. Allocation/error details and other commands do not determine the valid input result.

The excerpt contains 4200 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
