`counts[5] = {0}` initializes every element to zero, including index 3 for D in `ABCDF`. The grade mapping increments `counts[g]`; the final five-entry loop reads D as `counts[3]` even when no score entered that grade. Reestablish all five zeros before processing a second report (for example by clearing reused storage), or each nonzero grade total doubles. Present initialization already supplies the absent D zero.



The excerpt preserves complete source lines in their source order. Only the named inputs, decisions, updates and output operations needed for this question are retained; unrelated calculations, entry-point scaffolding and unused output are omitted. Standard language and library semantics supply the meaning of the retained operators and APIs, without their implementation bodies. Each selected operation establishes a fact used above; replacing these lines with callers alone would omit that fact.
