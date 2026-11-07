The decoder already reads encoded[0..len] only. Splitting by ASCII space yields full tokens; `/` writes a word space, while std.mem.eql compares token length and contents, never prefixes. The table prefix plus alphabet establishes `.` -> E and `.-` -> A. Accept standalone Morse by providing its slice directly to this tokenizer; keep the whole-token reverse lookup and output joining. No original-message fallback is present, and the encoder body/remaining table entries are unnecessary.



The excerpt preserves complete source lines in their source order. Only the named inputs, decisions, updates and output operations needed for this question are retained; unrelated calculations, entry-point scaffolding and unused output are omitted. Standard language and library semantics supply the meaning of the retained operators and APIs, without their implementation bodies. Each selected operation establishes a fact used above; replacing these lines with callers alone would omit that fact.
