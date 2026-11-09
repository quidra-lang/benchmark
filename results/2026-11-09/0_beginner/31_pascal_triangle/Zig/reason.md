`previous` starts with zeros and previous[0]=1; row 0 explicitly gets endpoint 1 and is saved as previous. Every row explicitly sets row[0] and row[n] to 1. At n=1 the n>1 guard suppresses all interior reads, so row 1 is 1,1. For later rows the 1..n range adds only valid preceding neighbors.



The excerpt preserves complete source lines in their source order. Only the named inputs, decisions, updates and output operations needed for this question are retained; unrelated calculations, entry-point scaffolding and unused output are omitted. Standard language and library semantics supply the meaning of the retained operators and APIs, without their implementation bodies. Each selected operation establishes a fact used above; replacing these lines with callers alone would omit that fact.
