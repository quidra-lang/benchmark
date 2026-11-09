Rename the introduced MINSTD binding state (seed 42) to rng_state and both left/right references in each recurrence, plus reads for arrival-gap modulo 5 and service modulo 7. `arrival` is independently initialized zero and accumulates those generated gaps; it is elapsed arrival time, not random generator state. Its name and all its own references stay unchanged. The exact declarations and random updates/reads establish this one-name distinction without customer scheduling.



The excerpt preserves complete source lines in their source order. Only the named inputs, decisions, updates and output operations needed for this question are retained; unrelated calculations, entry-point scaffolding and unused output are omitted. Standard language and library semantics supply the meaning of the retained operators and APIs, without their implementation bodies. Each selected operation establishes a fact used above; replacing these lines with callers alone would omit that fact.
