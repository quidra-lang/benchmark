# Task B: 56_permutations / J

Start with an empty prefix, no used characters and sequence number zero. At each depth try unused ABCD positions in order, so the first completion is `1: ABCD`. Recursion exhausts choices below A, ending that group with ADCB; restoring those choices permits B as the next first character and BACD as its first completion. Every leaf has four distinct characters; the 4×3×2×1 branches yield 24 lines, ending `24: DCBA`.

used is a local value updated to 1 before recursion and restored to 0 afterward; count is threaded through recursive return values, and the prefix is extended by value.

Evidence is from `main.ijs`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17.

- L1: `permutations =: 3 : 0`
- L2: `'prefix used count' =. y`
- L3: `if. 4=#prefix do.`
- L4: `count =. >:count`
- L5: `smoutput (":count),': ',prefix`
- L6: `count return.`
- L7: `end.`
- L8: `for_i. i.4 do.`
- L9: `if. -.i{used do.`
- L10: `used =. 1 i}used`
- L11: `count =. permutations (prefix,i{'ABCD');used;count`
- L12: `used =. 0 i}used`
- L13: `end.`
- L14: `end.`
- L15: `count`
- L16: `)`
- L17: `count =: permutations '';(4$0);0`

Minimization: The entry state and full small recursive enumerator are necessary to establish numbering, choice/restoration and exhaustiveness. No unrelated program logic or fallback selection is present. The selected complete original lines, in source order, cost 159 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 159, and the complete source costs 159. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
