# Task B source selection

## Common answer requirements

Locate the nonfinal multiword spacing branch and remainder-gap test; change only extra-space allocation to rightmost gaps, preserving base spacing and all other layout.

These answer requirements are identical for all twenty languages. The Task B assumptions apply; this is source analysis, not execution or verification of Task A.

## Supported answer and change analysis

Keep quotient base and remainder extra. For zero-based gap index g among gaps gaps, award the extra space when g >= gaps-extra instead of g < extra. For one-based gap index i use i > gaps-extra instead of i <= extra. Where i is a word index, account for whether spacing is emitted before or after that word. Restrict the change to the existing fully justified branch; packing, final/single-word padding, width and framing do not need edits.



## Source evidence and dependencies

The selected locations in `main.ts` are L21, L23, L24, L25, L27, L28. Each retained line below supplies the indicated operation, condition, declaration, data value, or enclosing branch needed to connect the answer to this implementation:

- L21: `if (index === lines.length - 1 || words.length === 1) {`. This line defines the exceptional-line guard, gap count/base/remainder or gap index used by the affected spacing test; these distinguish rightmost-gap allocation from simply reversing words or changing packing.
- L23: `} else {`. This line defines the exceptional-line guard, gap count/base/remainder or gap index used by the affected spacing test; these distinguish rightmost-gap allocation from simply reversing words or changing packing.
- L24: `const spaces = width - words.reduce((sum, word) => sum + word.length, 0);`. This line defines the exceptional-line guard, gap count/base/remainder or gap index used by the affected spacing test; these distinguish rightmost-gap allocation from simply reversing words or changing packing.
- L25: `const gaps = words.length - 1, base = Math.floor(spaces / gaps), extra = spaces % gaps;`. This line defines the exceptional-line guard, gap count/base/remainder or gap index used by the affected spacing test; these distinguish rightmost-gap allocation from simply reversing words or changing packing.
- L27: `for (let gap = 0; gap < gaps; gap++) {`. This line defines the exceptional-line guard, gap count/base/remainder or gap index used by the affected spacing test; these distinguish rightmost-gap allocation from simply reversing words or changing packing.
- L28: `text += " ".repeat(base + (gap < extra ? 1 : 0)) + words[gap + 1];`. This line defines the exceptional-line guard, gap count/base/remainder or gap index used by the affected spacing test; these distinguish rightmost-gap allocation from simply reversing words or changing packing.

## Language semantics and minimization

Use the language's ordinary expression evaluation, indexing, comparison, assignment, iteration and control-flow semantics, and the documented semantics of the standard-library operations shown in the excerpt. User-defined behavior needed for the answer is included rather than inferred solely from a helper name. Source lines need not form a standalone compilable program. Unrelated input/output setup, imports, whitespace, and purely structural closing lines are omitted unless they occur on a necessary complete line. The analysis identifies the affected logic; no replacement program is supplied.

`metric/tokenizer.py`'s `tokenize` reports **187 tokens** for the selected original complete lines. A contiguous-context alternative spanning L21–L28 costs **224 tokens**; the entire source costs **589 tokens**. The selected set plus the additional context line L1 costs **193 tokens**. That extra line does not add an answer requirement. These comparisons favor the retained dependency slice over context-heavy alternatives. Every selected substantive line was reviewed for the facts or dependency it contributes. This is a minimized sufficient selection among reviewed alternatives, not a proof of a global mathematical minimum.
