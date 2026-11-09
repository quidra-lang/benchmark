# Task B: 52_polygon_area / J

For an empty vertex sequence the edge loop has zero iterations. Therefore neither the first vertex access nor the last-to-first/wrap access inside its body is evaluated; there is no prior first-vertex read and no explicit rejection. The initialized twice-area/cross-sum 0 and perimeter 0.0 reach formatting, giving polygon 1 area=0.0 and perimeter=0.000. These are default results, not a validation error.

i.#polygon is empty at length zero. Both polygon reads and the modulus-based next index lie inside that loop.

Evidence is from `main.ijs`, L4,L5,L6,L7,L8,L9,L10,L16,L17,L18.

- L4: `polygon =. >k{polygons`
- L5: `crosssum =. 0`
- L6: `perimeter =. 0.0`
- L7: `for_i. i.#polygon do.`
- L8: `j =. (#polygon)|i+1`
- L9: `'x1 y1' =. i{polygon`
- L10: `'x2 y2' =. j{polygon`
- L16: `end.`
- L17: `area =. (|crosssum)%2`
- L18: `smoutput 'polygon ',(":>:k),': area=',(, '1' 8!:2 area),' perimeter=',, '3' 8!:2 perimeter`

Minimization: Initialization, loop entry, the endpoint accesses and loop exit/output are enough to determine empty behavior. Edge arithmetic inside the skipped body and actual nonempty polygon literals are unnecessary. The selected complete original lines, in source order, cost 150 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 219, and the complete source costs 337. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
