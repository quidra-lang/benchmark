# Task B selection: 86_convex_hull / J

## Common answer requirements

Trace the three x=-6 points in sorted forward/reverse chains; identify collinear rejection cross comparison; explain endpoint removal and concatenation establishing lexicographic start and counterclockwise order.

## Answer and source dependencies

Sorting by x then y presents (-6,-2), (-6,1), (-6,3) to the lower chain. The third gives cross product zero, so the middle point is popped; a later point to their right also removes (-6,3) from the lower chain. The reversed upper scan encounters (-6,3), then (-6,1), then (-6,-2); again the zero-cross rule removes the middle boundary point. The <=0 pop comparison removes clockwise and collinear turns, retaining strictly counterclockwise corners. Each completed chain shares its two endpoints with the other. Omitting each chain’s final endpoint and concatenating lower then upper includes each shared endpoint once, begins at lexicographically smallest (-6,-2), and goes counterclockwise around the hull.



## Scope and dependency evidence checked after independent review

Point record/tuple field associations establish which supplied coordinate is x and which is y. Cross/comparator/chain definitions terminate before their uses; each pop loop ends before the new point is appended, each chain traversal ends before return or joining, and the x-sort branch ends before its y fallback. Sorted x=-6 points are(-6,-2),(-6,1),(-6,3): cross0 removes the middle point; the next rightward point removes the upper endpoint from the lower chain, while the reverse upper pass retains it and removes the middle collinear point. Dropping each completed chain final endpoint before concatenating lower then upper keeps each extreme once, starts at(-6,-2), and follows counterclockwise order.

Source: `main.ijs`. Selected original locations: L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20.

- L1: `cross =: 3 : 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `  'o a b' =. y` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `  ((0{a-o)*1{b-o)-((1{a-o)*0{b-o)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `)` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L5: `chain =: 3 : 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `  result =. 0 2$0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `  for_point. y do.` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    while. (#result)>:2 do.` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `      if. (cross (_2{.result),point)>0 do. break. end.` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `      result =. }:result` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    end.` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L12: `    result =. result,point` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `  end.` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L14: `  result` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `)` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L16: `points =: 15 2$3 2 _6 1 8 4 0 0 _3 7 4 _3 1 _5 _2 1 5 6 _6 _2 2 _2 7 _1 _3 4 2 8 _6 3` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `points =: /:~points` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `lower =: }:chain points` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `upper =: }:chain |.points` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `hull =: lower,upper` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **270 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 260 tokens. The contiguous original span L1–L20 costs 270 tokens; the complete original source costs 454 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 260 tokens; removes `cross =: 3 : 0` from the dependency chain described above.
- Without L2: 257 tokens; removes `'o a b' =. y` from the dependency chain described above.
- Without L3: 237 tokens; removes `((0{a-o)*1{b-o)-((1{a-o)*0{b-o)` from the dependency chain described above.
- Without L4: 268 tokens; removes `)` from the dependency chain described above.
- Without L5: 260 tokens; removes `chain =: 3 : 0` from the dependency chain described above.
- Without L6: 259 tokens; removes `result =. 0 2$0` from the dependency chain described above.
- Without L7: 260 tokens; removes `for_point. y do.` from the dependency chain described above.
- Without L8: 258 tokens; removes `while. (#result)>:2 do.` from the dependency chain described above.
- Without L9: 245 tokens; removes `if. (cross (_2{.result),point)>0 do. break. end.` from the dependency chain described above.
- Without L10: 261 tokens; removes `result =. }:result` from the dependency chain described above.
- Without L11: 267 tokens; removes `end.` from the dependency chain described above.
- Without L12: 261 tokens; removes `result =. result,point` from the dependency chain described above.
- Without L13: 267 tokens; removes `end.` from the dependency chain described above.
- Without L14: 267 tokens; removes `result` from the dependency chain described above.
- Without L15: 268 tokens; removes `)` from the dependency chain described above.
- Without L16: 190 tokens; removes `points =: 15 2$3 2 _6 1 8 4 0 0 _3 7 4 _3 1 _5 _2 1 5 6 _6 _2 2 _2 7 _1 _3 4 2 8 _6 3` from the dependency chain described above.
- Without L17: 262 tokens; removes `points =: /:~points` from the dependency chain described above.
- Without L18: 261 tokens; removes `lower =: }:chain points` from the dependency chain described above.
- Without L19: 260 tokens; removes `upper =: }:chain |.points` from the dependency chain described above.
- Without L20: 262 tokens; removes `hull =: lower,upper` from the dependency chain described above.
