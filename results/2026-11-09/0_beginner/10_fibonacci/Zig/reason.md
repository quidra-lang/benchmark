The integer states begin at a=1, b=1, sum=0. Thirty iterations expose `a` as the next sequence term, add it to the separate total, then replace `(a,b)` with `(b,a+b)` using a temporary. Thus F(3)=2 and the total is 2178308. The `u32` declarations enforce nonnegative integer terms and total; no floating conversion occurs. The bound and initialization establish the count and exact value behavior; unrelated line-format details are omitted.



The excerpt preserves complete source lines in their source order. Only the named inputs, decisions, updates and output operations needed for this question are retained; unrelated calculations, entry-point scaffolding and unused output are omitted. Standard language and library semantics supply the meaning of the retained operators and APIs, without their implementation bodies. Each selected operation establishes a fact used above; replacing these lines with callers alone would omit that fact.
