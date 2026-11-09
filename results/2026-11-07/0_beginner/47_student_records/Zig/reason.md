After constructing students and before sorting/output, iterate with mutable element access and rebind each `name` slice to `std.mem.trim(u8, student.name, " ")`. This trims only outer ASCII spaces and preserves character case; []const u8 prevents modifying underlying text but the field slice can be rebound through a mutable record. The record type and mutable array declaration establish this local normalization point; scores and comparator logic remain unchanged.



The excerpt preserves complete source lines in their source order. Only the named inputs, decisions, updates and output operations needed for this question are retained; unrelated calculations, entry-point scaffolding and unused output are omitted. Standard language and library semantics supply the meaning of the retained operators and APIs, without their implementation bodies. Each selected operation establishes a fact used above; replacing these lines with callers alone would omit that fact.
