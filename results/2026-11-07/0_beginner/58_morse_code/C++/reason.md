The input stream is constructed from encoded Morse alone. Formatted extraction yields whole space-delimited tokens; `/` appends a word space, and std::find compares entire strings in the table. The first table entries establish `.-`=A and `.`=E, so neither can match the other’s prefix. Expose standalone Morse as the stream input and keep this reverse lookup/joining; original message letters are not used as fallback. Other table rows and the encoder body are unnecessary.



The excerpt preserves complete source lines in their source order. Only the named inputs, decisions, updates and output operations needed for this question are retained; unrelated calculations, entry-point scaffolding and unused output are omitted. Standard language and library semantics supply the meaning of the retained operators and APIs, without their implementation bodies. Each selected operation establishes a fact used above; replacing these lines with callers alone would omit that fact.
