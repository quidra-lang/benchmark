# Task B: 40_binary_search / J

Initial low/high are zero-based 0 and 15, so floor((0+15)/2)=7. This is a recorded position, while the corresponding array element is 31 at one-based ordinal 8. The probe list stores midpoint itself, not the fetched value; later comparisons are outside the requested first-midpoint analysis.

J reads midpoint{values directly because its arrays are zero-indexed, and records midpoint in probes.

Evidence is from `main.ijs`, L2,L4,L5,L9,L10,L11.

- L2: `values =. 3 8 11 15 19 24 27 31 36 42 47 53 58 64 70 77`
- L4: `lo =. 0`
- L5: `hi =. 15`
- L9: `mid =. <.(lo+hi)%2`
- L10: `probes =. probes,mid`
- L11: `if. (mid{values)=target do. found =. mid break.`

Minimization: The array, initial endpoints, midpoint computation, probe append and first array read establish both representations. Later branch updates and output are omitted. The selected complete original lines, in source order, cost 113 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 162, and the complete source costs 288. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
