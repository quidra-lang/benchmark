# Task B: 86_convex_hull / J

First sort coordinate pairs lexicographically, then traverse that sorted collection in reverse; the first two points are (8,4) and (7,-1). For each candidate, compare it with the last two chain points via the signed cross product. While chain length permits and cross<=0, remove the last chain point repeatedly, then append the current point. The reversal applies to coordinate-sorted order, not the original input order. Stop after the upper chain is built.

The chain helper's while/pop behavior is user-defined; upper receives |.points only after points has been sorted.

Evidence is from `main.ijs`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L16,L17,L19.

- L1: `cross =: 3 : 0`
- L2: `'o a b' =. y`
- L3: `((0{a-o)*1{b-o)-((1{a-o)*0{b-o)`
- L4: `)`
- L5: `chain =: 3 : 0`
- L6: `result =. 0 2$0`
- L7: `for_point. y do.`
- L8: `while. (#result)>:2 do.`
- L9: `if. (cross (_2{.result),point)>0 do. break. end.`
- L10: `result =. }:result`
- L11: `end.`
- L12: `result =. result,point`
- L13: `end.`
- L14: `result`
- L16: `points =: 15 2$3 2 _6 1 8 4 0 0 _3 7 4 _3 1 _5 _2 1 5 6 _6 _2 2 _2 7 _1 _3 4 2 8 _6 3`
- L17: `points =: /:~points`
- L19: `upper =: }:chain |.points`

Minimization: Cross product, full small chain helper, point data/sort and upper call are required to establish reverse order and repeated removal. Lower-chain concatenation, area and output are omitted. The selected complete original lines, in source order, cost 251 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 262, and the complete source costs 454. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
