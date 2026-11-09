The base state is one route of length zero from the start cell to itself. Each mode creates a zero table and explicitly assigns dp[0][0]=1 in the top-left branch. Thus both modes share the same one-route base state rather than zero. Only this initialization and its per-case location are needed; recurrence propagation is outside the question.



The excerpt preserves complete source lines in their source order. Only the named inputs, decisions, updates and output operations needed for this question are retained; unrelated calculations, entry-point scaffolding and unused output are omitted. Standard language and library semantics supply the meaning of the retained operators and APIs, without their implementation bodies. Each selected operation establishes a fact used above; replacing these lines with callers alone would omit that fact.
