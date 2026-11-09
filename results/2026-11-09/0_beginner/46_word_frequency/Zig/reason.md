getOrPut retrieves or inserts the normalized word entry. A new cat entry is detected by !found_existing and its u32 value explicitly set to zero before incrementing to 1. The second cat reuses the same key, skips zeroing and increments the stored value through its pointer to 2. Neither the map API alone nor an uninitialized inserted value supplies zero; the explicit branch is necessary. Ranking and tokenization are excluded.



The excerpt preserves complete source lines in their source order. Only the named inputs, decisions, updates and output operations needed for this question are retained; unrelated calculations, entry-point scaffolding and unused output are omitted. Standard language and library semantics supply the meaning of the retained operators and APIs, without their implementation bodies. Each selected operation establishes a fact used above; replacing these lines with callers alone would omit that fact.
