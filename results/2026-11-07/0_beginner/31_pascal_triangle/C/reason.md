`row` starts [1,0,...] by aggregate initialization. At n=0 the descending loop does nothing. At n=1 only k=1 is updated to 0+1=1; k=0 stays 1. The condition k>0 prevents access to row[-1], and descending updates preserve predecessor values for interior sums. Thus row 1 has endpoints 1,1 without nonexistent neighbors.



The excerpt preserves complete source lines in their source order. Only the named inputs, decisions, updates and output operations needed for this question are retained; unrelated calculations, entry-point scaffolding and unused output are omitted. Standard language and library semantics supply the meaning of the retained operators and APIs, without their implementation bodies. Each selected operation establishes a fact used above; replacing these lines with callers alone would omit that fact.
