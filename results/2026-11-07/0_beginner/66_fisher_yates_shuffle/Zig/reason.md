At i=1 the source first advances MINSTD state, then uses modulo i+1=2 so j can only be 0 or 1, then swaps. A j=1 self-swap leaves the deck unchanged but still consumes that prior random update. The decrement changes i to 0 and the loop guard excludes it, so no i=0 random value is consumed. Only the local update/order and boundary are needed, not seed/deck traversal.



The excerpt preserves complete source lines in their source order. Only the named inputs, decisions, updates and output operations needed for this question are retained; unrelated calculations, entry-point scaffolding and unused output are omitted. Standard language and library semantics supply the meaning of the retained operators and APIs, without their implementation bodies. Each selected operation establishes a fact used above; replacing these lines with callers alone would omit that fact.
