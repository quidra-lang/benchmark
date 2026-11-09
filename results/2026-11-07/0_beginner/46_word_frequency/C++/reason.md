Map indexing `counts[w]` inserts an absent key with a value-initialized int, hence zero; prefix increment makes the first normalized cat count 1. Reusing the equal string key returns the existing int and increments it to 2. This mutates the map’s stored value. Standard map semantics replace the need for explicit absent-key implementation or ranking code.



The excerpt preserves complete source lines in their source order. Only the named inputs, decisions, updates and output operations needed for this question are retained; unrelated calculations, entry-point scaffolding and unused output are omitted. Standard language and library semantics supply the meaning of the retained operators and APIs, without their implementation bodies. Each selected operation establishes a fact used above; replacing these lines with callers alone would omit that fact.
