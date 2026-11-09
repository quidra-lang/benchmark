The unformatted `mean` is a double because the sum is converted before division. `printf("%.2f\n", mean)` converts it to fixed decimal text rounded to two fractional digits, retaining a trailing zero. The only suffix is LF, so no space or separator is added; formatting does not replace the numeric value.



The excerpt preserves complete source lines in their source order. Only the named inputs, decisions, updates and output operations needed for this question are retained; unrelated calculations, entry-point scaffolding and unused output are omitted. Standard language and library semantics supply the meaning of the retained operators and APIs, without their implementation bodies. Each selected operation establishes a fact used above; replacing these lines with callers alone would omit that fact.
