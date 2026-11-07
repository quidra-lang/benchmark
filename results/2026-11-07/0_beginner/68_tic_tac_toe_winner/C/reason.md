snprintf copies the selected board’s three row strings into an independent character array cells. The winner test only reads cells at the selected triple and copies the first character into a scalar; it never writes board or cells. Thus a row/diagonal check cannot affect the next check’s intended board data. Index triples, construction and comparison establish storage behavior; unrelated full input literals and final labels are omitted.



The excerpt preserves complete source lines in their source order. Only the named inputs, decisions, updates and output operations needed for this question are retained; unrelated calculations, entry-point scaffolding and unused output are omitted. Standard language and library semantics supply the meaning of the retained operators and APIs, without their implementation bodies. Each selected operation establishes a fact used above; replacing these lines with callers alone would omit that fact.
