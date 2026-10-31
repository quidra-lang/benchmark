# Task B selection: 85_text_justify / Rust

## Common answer requirements

Locate the nonfinal multiword spacing branch and remainder-gap test; change only extra-space allocation to rightmost gaps, preserving base spacing and all other layout.

## Answer and source dependencies

Keep quotient base and remainder extra. For zero-based gap index g among gaps gaps, award the extra space when g >= gaps-extra instead of g < extra. For one-based gap index i use i > gaps-extra instead of i <= extra. Where i is a word index, account for whether spacing is emitted before or after that word. Restrict the change to the existing fully justified branch; packing, final/single-word padding, width and framing do not need edits.



## Scope and dependency evidence checked after independent review

Keep the existing final-line/single-word branch and floor-division base space count. Replace only the remainder predicate: zero-based gap g receives1 iff g>=gaps-extra; one-based g receives1 iff g>gaps-extra. At extra0 neither condition selects any gap. The retained loop header establishes whether the source gap index is zero- or one-based, and the C#/Rust delimiters complete the branch/expression containing the affected repetition count.

Source: `main.rs`. Selected original locations: L11,L12,L17,L18,L19,L20,L21.

- L11: `        let gaps = end - start - 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `        let last = end == words.len();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `                let spaces = if last || gaps == 0 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `                    1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `                } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `                    (30 - letters) / gaps + usize::from(i - start < (30 - letters) % gaps)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `                };` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.

## Minimization and language semantics

The final selected excerpt measures **132 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 125 tokens. The contiguous original span L11–L21 costs 196 tokens; the complete original source costs 586 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L11: 113 tokens; removes `let gaps = end - start - 1;` from the dependency chain described above.
- Without L12: 113 tokens; removes `let last = end == words.len();` from the dependency chain described above.
- Without L17: 108 tokens; removes `let spaces = if last || gaps == 0 {` from the dependency chain described above.
- Without L18: 125 tokens; removes `1` from the dependency chain described above.
- Without L19: 122 tokens; removes `} else {` from the dependency chain described above.
- Without L20: 86 tokens; removes `(30 - letters) / gaps + usize::from(i - start < (30 - letters) % gaps)` from the dependency chain described above.
- Without L21: 125 tokens; removes `};` from the dependency chain described above.
