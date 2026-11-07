The stored input -456789 is formatted as signed decimal text, with the initial sign excluded from the digit loop. Digits are traversed left-to-right; a comma appears before a digit only after at least one magnitude digit and with a multiple of three digits remaining. This yields `-456,789` plus LF. The first-digit guard prevents a comma immediately after the sign and placement before an existing digit prevents a final comma.



The excerpt preserves complete source lines in their source order. Only the named inputs, decisions, updates and output operations needed for this question are retained; unrelated calculations, entry-point scaffolding and unused output are omitted. Standard language and library semantics supply the meaning of the retained operators and APIs, without their implementation bodies. Each selected operation establishes a fact used above; replacing these lines with callers alone would omit that fact.
