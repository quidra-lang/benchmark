The second input has maximal runs 12 W, 1 B, 12 W, 3 B, encoding `12W1B12W3B`. The forward scan advances to the first unequal character for each run. strtol consumes the complete decimal prefix, then memset repeats the following encoded symbol. Decoder input comes from the encoded buffer/string, not original s. The line is `WWWWWWWWWWWWBWWWWWWWWWWWWBBB -> 12W1B12W3B -> WWWWWWWWWWWWBWWWWWWWWWWWWBBB` plus LF.



The excerpt preserves complete source lines in their source order. Only the named inputs, decisions, updates and output operations needed for this question are retained; unrelated calculations, entry-point scaffolding and unused output are omitted. Standard language and library semantics supply the meaning of the retained operators and APIs, without their implementation bodies. Each selected operation establishes a fact used above; replacing these lines with callers alone would omit that fact.
