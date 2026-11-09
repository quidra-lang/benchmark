# Task B: 71_knapsack_01 / J

Zero-initialized DP represents zero items and zero capacity. For the first tent (weight 10,value 120), capacities below 10 keep zero and capacities at least 10 compare zero against 120 plus the preceding-item zero state. Every later take/skip reads only the preceding item stage, preventing reuse of the same item. Traceback compares current with preceding-stage values, marks a differing item and subtracts its weight; the selected mask/names are finally read in original item order.

The named limit sizes and bounds the table; row item-1 provides both transition alternatives, and the Boolean chosen vector restores original name order after reverse traceback.

Evidence is from `main.ijs`, L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L28.

- L2: `names =. ;:'tent stove lantern rope camera blanket water'`
- L3: `weights =. 10 3 2 3 5 5 6`
- L4: `values =. 120 65 45 20 90 85 100`
- L5: `limit =. 20`
- L6: `dp =. (8,limit+1)$0`
- L7: `for_i. >:i.7 do.`
- L8: `weight =. (i-1){weights`
- L9: `value =. (i-1){values`
- L10: `for_capacity. i.limit+1 do.`
- L11: `best =. (<(i-1),capacity){dp`
- L12: `if. weight<:capacity do.`
- L13: `best =. best >. value+(<(i-1),capacity-weight){dp`
- L14: `end.`
- L15: `dp =. best (<i,capacity)}dp`
- L16: `end.`
- L17: `end.`
- L18: `chosen =. 7$0`
- L19: `capacity =. limit`
- L20: `for_i. |.>:i.7 do.`
- L21: `if. ((<i,capacity){dp)~:(<(i-1),capacity){dp do.`
- L22: `chosen =. 1 (i-1)}chosen`
- L23: `capacity =. capacity-(i-1){weights`
- L24: `end.`
- L25: `end.`
- L28: `smoutput 'items: ',}. ; (<' ') ,&.> chosen#names`

Minimization: Item identity/weight/value data, zero base, preceding-stage transition and traceback/name selection all belong to the requested stage chain. Final value/weight summary formatting is unnecessary where separately written. The selected complete original lines, in source order, cost 352 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 393, and the complete source costs 410. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
