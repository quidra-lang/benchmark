Value initialization in `counts{}` gives all five integers zero, including D at index 3 of `ABCDF`. The mapping increments `counts[g]`; the output loop reads all five counts including that unused grade. Clear every element before repeating the report, or recreate this value-initialized array, to avoid doubling counts. Existing initialization already guarantees the D zero.



The excerpt preserves complete source lines in their source order. Only the named inputs, decisions, updates and output operations needed for this question are retained; unrelated calculations, entry-point scaffolding and unused output are omitted. Standard language and library semantics supply the meaning of the retained operators and APIs, without their implementation bodies. Each selected operation establishes a fact used above; replacing these lines with callers alone would omit that fact.
