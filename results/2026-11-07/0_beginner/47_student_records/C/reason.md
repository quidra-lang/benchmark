Normalize each `students[i].name` after loading records and before sorting/output: trim only leading/trailing ASCII spaces while preserving letter case. The field is a pointer to const char, so do not overwrite literal storage or merely advance the start while leaving trailing spaces visible; produce a terminated owned trimmed copy and rebind the field. The existing Student name binding and its initialization suffice to identify this local change; scores/ranking need no edits.



The excerpt preserves complete source lines in their source order. Only the named inputs, decisions, updates and output operations needed for this question are retained; unrelated calculations, entry-point scaffolding and unused output are omitted. Standard language and library semantics supply the meaning of the retained operators and APIs, without their implementation bodies. Each selected operation establishes a fact used above; replacing these lines with callers alone would omit that fact.
