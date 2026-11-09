The source first orders the three sides ascending. Split its current `a+b<=c` rejection into equality -> `degenerate` and strict less-than -> `not a triangle`; only a+b>c continues to the existing side/angle classification. Supplied (3,8,5) sorts to (3,5,8) and reaches equality. Keep all other comparison boundaries intact. The ordered-side preparation and current validity gate are needed; the unchanged angle arithmetic is unnecessary to locate this split.



The excerpt preserves complete source lines in their source order. Only the named inputs, decisions, updates and output operations needed for this question are retained; unrelated calculations, entry-point scaffolding and unused output are omitted. Standard language and library semantics supply the meaning of the retained operators and APIs, without their implementation bodies. Each selected operation establishes a fact used above; replacing these lines with callers alone would omit that fact.
