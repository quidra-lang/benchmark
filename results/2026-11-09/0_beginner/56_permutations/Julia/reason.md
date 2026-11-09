# Task B: 56_permutations / Julia

Start with an empty prefix, no used characters and sequence number zero. At each depth try unused ABCD positions in order, so the first completion is `1: ABCD`. Recursion exhausts choices below A, ending that group with ADCB; restoring those choices permits B as the next first character and BACD as its first completion. Every leaf has four distinct characters; the 4×3×2×1 branches yield 24 lines, ending `24: DCBA`.

used is a shared Bool vector for this search and is explicitly reset after each recursive return; the nested counter increments once at each completed prefix.

Evidence is from `main.jl`, L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19.

- L2: `characters = collect("ABCD")`
- L3: `used = falses(4)`
- L4: `counter = 0`
- L5: `function visit(prefix)`
- L6: `if length(prefix) == 4`
- L7: `counter += 1`
- L8: `println(counter, ": ", prefix)`
- L9: `return`
- L10: `end`
- L11: `for i = 1:4`
- L12: `if !used[i]`
- L13: `used[i] = true`
- L14: `visit(string(prefix, characters[i]))`
- L15: `used[i] = false`
- L16: `end`
- L17: `end`
- L18: `end`
- L19: `visit("")`

Minimization: The entry state and full small recursive enumerator are necessary to establish numbering, choice/restoration and exhaustiveness. No unrelated program logic or fallback selection is present. The selected complete original lines, in source order, cost 171 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 171, and the complete source costs 182. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
