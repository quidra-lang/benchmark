The selected sort mutates the existing teams ordering container in place; it does not return a separate sorted order. Preserve the original by copying its ordering storage before sorting and sort that copy for standings. A separate Team array copies numeric fields; name pointers can still share immutable names without sharing slot order. No statistics recomputation or comparator changes are needed. The container declaration plus sort call suffices; comparator internals do not affect aliasing.



The excerpt preserves complete source lines in their source order. Only the named inputs, decisions, updates and output operations needed for this question are retained; unrelated calculations, entry-point scaffolding and unused output are omitted. Standard language and library semantics supply the meaning of the retained operators and APIs, without their implementation bodies. Each selected operation establishes a fact used above; replacing these lines with callers alone would omit that fact.
