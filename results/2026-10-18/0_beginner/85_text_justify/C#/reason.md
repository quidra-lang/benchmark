# Task B selection: 85_text_justify / C#

## Common answer requirements

Locate the nonfinal multiword spacing branch and remainder-gap test; change only extra-space allocation to rightmost gaps, preserving base spacing and all other layout.

## Answer and source dependencies

Keep quotient base and remainder extra. For zero-based gap index g among gaps gaps, award the extra space when g >= gaps-extra instead of g < extra. For one-based gap index i use i > gaps-extra instead of i <= extra. Where i is a word index, account for whether spacing is emitted before or after that word. Restrict the change to the existing fully justified branch; packing, final/single-word padding, width and framing do not need edits.



## Scope and dependency evidence checked after independent review

Keep the existing final-line/single-word branch and floor-division base space count. Replace only the remainder predicate: zero-based gap g receives1 iff g>=gaps-extra; one-based g receives1 iff g>gaps-extra. At extra0 neither condition selects any gap. The retained loop header establishes whether the source gap index is zero- or one-based, and the C#/Rust delimiters complete the branch/expression containing the affected repetition count.

Source: `Program.cs`. Selected original locations: L29,L30,L32,L33,L34,L35,L37,L38,L39.

- L29: `    if (i == lines.Count - 1 || words.Count == 1)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `    {` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L32: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L33: `    else` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L34: `    {` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L35: `        int spaces = 30 - words.Sum(w => w.Length), gaps = words.Count - 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `        for (int j = 1; j < words.Count; j++)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `        {` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L39: `            line.Append(' ', spaces / gaps + (j - 1 < spaces % gaps ? 1 : 0));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **156 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 143 tokens. The contiguous original span L29–L39 costs 202 tokens; the complete original source costs 666 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L29: 129 tokens; removes `if (i == lines.Count - 1 || words.Count == 1)` from the dependency chain described above.
- Without L30: 153 tokens; removes `{` from the dependency chain described above.
- Without L32: 153 tokens; removes `}` from the dependency chain described above.
- Without L33: 153 tokens; removes `else` from the dependency chain described above.
- Without L34: 153 tokens; removes `{` from the dependency chain described above.
- Without L35: 116 tokens; removes `int spaces = 30 - words.Sum(w => w.Length), gaps = words.Count - 1;` from the dependency chain described above.
- Without L37: 129 tokens; removes `for (int j = 1; j < words.Count; j++)` from the dependency chain described above.
- Without L38: 152 tokens; removes `{` from the dependency chain described above.
- Without L39: 110 tokens; removes `line.Append(' ', spaces / gaps + (j - 1 < spaces % gaps ? 1 : 0));` from the dependency chain described above.
