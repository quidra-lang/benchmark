# Task B selection: 85_text_justify / Julia

## Common answer requirements

Locate the nonfinal multiword spacing branch and remainder-gap test; change only extra-space allocation to rightmost gaps, preserving base spacing and all other layout.

## Answer and source dependencies

Keep quotient base and remainder extra. For zero-based gap index g among gaps gaps, award the extra space when g >= gaps-extra instead of g < extra. For one-based gap index i use i > gaps-extra instead of i <= extra. Where i is a word index, account for whether spacing is emitted before or after that word. Restrict the change to the existing fully justified branch; packing, final/single-word padding, width and framing do not need edits.



## Scope and dependency evidence checked after independent review

Keep the existing final-line/single-word branch and floor-division base space count. Replace only the remainder predicate: zero-based gap g receives1 iff g>=gaps-extra; one-based g receives1 iff g>gaps-extra. At extra0 neither condition selects any gap. The retained loop header establishes whether the source gap index is zero- or one-based, and the C#/Rust delimiters complete the branch/expression containing the affected repetition count.

Source: `main.jl`. Selected original locations: L17,L19,L20,L21,L23,L25.

- L17: `        if number == length(lines) || length(words) == 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `        else` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L20: `            spaces = 30-sum(length, words)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `            base, extra = divrem(spaces, length(words)-1)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `            for i in eachindex(words)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `                i < length(words) && print(output, repeat(" ", base+(i <= extra)))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **122 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 108 tokens. The contiguous original span L17–L25 costs 173 tokens; the complete original source costs 520 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L17: 98 tokens; removes `if number == length(lines) || length(words) == 1` from the dependency chain described above.
- Without L19: 118 tokens; removes `else` from the dependency chain described above.
- Without L20: 104 tokens; removes `spaces = 30-sum(length, words)` from the dependency chain described above.
- Without L21: 99 tokens; removes `base, extra = divrem(spaces, length(words)-1)` from the dependency chain described above.
- Without L23: 108 tokens; removes `for i in eachindex(words)` from the dependency chain described above.
- Without L25: 83 tokens; removes `i < length(words) && print(output, repeat(" ", base+(i <= extra)))` from the dependency chain described above.
