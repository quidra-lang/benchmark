# Task B selection: 85_text_justify / J

## Common answer requirements

Locate the nonfinal multiword spacing branch and remainder-gap test; change only extra-space allocation to rightmost gaps, preserving base spacing and all other layout.

## Answer and source dependencies

Keep quotient base and remainder extra. For zero-based gap index g among gaps gaps, award the extra space when g >= gaps-extra instead of g < extra. For one-based gap index i use i > gaps-extra instead of i <= extra. Where i is a word index, account for whether spacing is emitted before or after that word. Restrict the change to the existing fully justified branch; packing, final/single-word padding, width and framing do not need edits.



## Scope and dependency evidence checked after independent review

Keep the existing final-line/single-word branch and floor-division base space count. Replace only the remainder predicate: zero-based gap g receives1 iff g>=gaps-extra; one-based g receives1 iff g>gaps-extra. At extra0 neither condition selects any gap. The retained loop header establishes whether the source gap index is zero- or one-based, and the C#/Rust delimiters complete the branch/expression containing the affected repetition count.

Source: `main.ijs`. Selected original locations: L25,L28,L30,L31,L32,L33,L35,L36.

- L25: `    if. ((index+1)=#lines)+.1=#line do.` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `    else.` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `      gaps =. <:#line` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `      spaces =. 30-letters` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `      base =. <.spaces%gaps` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `      extra =. gaps|spaces` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `      for_i. i.#line do.` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `        if. i>0 do. result =. result,(base+i<:extra)$' ' end.` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **107 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 94 tokens. The contiguous original span L25–L36 costs 172 tokens; the complete original source costs 572 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L25: 88 tokens; removes `if. ((index+1)=#lines)+.1=#line do.` from the dependency chain described above.
- Without L28: 104 tokens; removes `else.` from the dependency chain described above.
- Without L30: 97 tokens; removes `gaps =. <:#line` from the dependency chain described above.
- Without L31: 96 tokens; removes `spaces =. 30-letters` from the dependency chain described above.
- Without L32: 96 tokens; removes `base =. <.spaces%gaps` from the dependency chain described above.
- Without L33: 97 tokens; removes `extra =. gaps|spaces` from the dependency chain described above.
- Without L35: 94 tokens; removes `for_i. i.#line do.` from the dependency chain described above.
- Without L36: 77 tokens; removes `if. i>0 do. result =. result,(base+i<:extra)$' ' end.` from the dependency chain described above.
