# Task B: 18_number_with_commas / J

The stored negative input makes the named sign decision true. Formatting uses abs(-456789)=456789, so grouping digits from the right creates 456,789 before the minus sign is reattached. The completed line is `-456,789`. The sign is outside the grouped magnitude; grouping inserts separators only between nonempty three-digit groups, so neither a comma after the sign nor a final comma occurs.

The magnitude uses the c0 comma-grouping format on |n; a separate sign fragment is prepended before smoutput.

Evidence is from `main.ijs`, L2,L3,L4,L5.

- L2: `for_n. 0 7 999 1000 _456789 3141592 9876543210 do.`
- L3: `negative =. n<0`
- L4: `magnitude =. , 'c0' 8!:2 |n`
- L5: `smoutput (negative#'-'),magnitude`

Minimization: The input binder, sign decision, magnitude formatting and output cover the complete requested path. Sign behavior cannot be inferred from magnitude formatting alone, so both stages are retained. The selected complete original lines, in source order, cost 88 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 88, and the complete source costs 108. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
