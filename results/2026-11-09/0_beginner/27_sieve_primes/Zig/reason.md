Allocate limit+2 flags, initialize the unused position 0 false, and translate all logical k flags to k+1. The flags for 0,1,7,49,200 reside at 1,2,8,50,201. Set translated 0/1 false, retain translated 2..200 true before marking, and shift p/m reads and writes plus prime retrieval. Count only translated flags or keep the unused flag false. Logical ranges and printed p remain 2..200 in increasing order: 7 is prime, 49 and 200 composite. Formatting branches are unaffected.



The excerpt preserves complete source lines in their source order. Only the named inputs, decisions, updates and output operations needed for this question are retained; unrelated calculations, entry-point scaffolding and unused output are omitted. Standard language and library semantics supply the meaning of the retained operators and APIs, without their implementation bodies. Each selected operation establishes a fact used above; replacing these lines with callers alone would omit that fact.
