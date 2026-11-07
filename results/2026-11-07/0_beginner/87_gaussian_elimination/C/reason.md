The factor is captured once before entry updates as `f=a[i][k]/a[k][k]`. With the swapped pivot coefficient 4 and next-row coefficient 2, f=0.5. Updating j=k zeros that row coefficient (2-0.5*4). Recomputing a ratio afterward would incorrectly give zero for later columns; the loop instead reuses the previously captured f throughout. The one declaration and consuming loop establish this read-before-write dependency; pivot search and other systems are outside the question.



The excerpt preserves complete source lines in their source order. Only the named inputs, decisions, updates and output operations needed for this question are retained; unrelated calculations, entry-point scaffolding and unused output are omitted. Standard language and library semantics supply the meaning of the retained operators and APIs, without their implementation bodies. Each selected operation establishes a fact used above; replacing these lines with callers alone would omit that fact.
