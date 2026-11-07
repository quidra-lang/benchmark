The exact `usize` operands are word count and total token byte lengths. `@floatFromInt` in f64 context converts both before `/`, so `average` is already a real quotient and integer counts remain unchanged. Preserve these pre-division conversions in a port; converting after integer division would be too late. Token scanning and output formatting are not required for this arithmetic fact.



The excerpt preserves complete source lines in their source order. Only the named inputs, decisions, updates and output operations needed for this question are retained; unrelated calculations, entry-point scaffolding and unused output are omitted. Standard language and library semantics supply the meaning of the retained operators and APIs, without their implementation bodies. Each selected operation establishes a fact used above; replacing these lines with callers alone would omit that fact.
