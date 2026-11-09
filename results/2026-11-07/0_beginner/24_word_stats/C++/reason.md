`total` stores summed word sizes and `count` the exact integer word count. `static_cast<double>(total) / count` already converts an operand before division, making the quotient real under C++ arithmetic rules. Keep an equivalent conversion before `/` in the port, rather than converting an already truncated result. Longest/shortest comparisons and formatting are unnecessary for this expression question.



The excerpt preserves complete source lines in their source order. Only the named inputs, decisions, updates and output operations needed for this question are retained; unrelated calculations, entry-point scaffolding and unused output are omitted. Standard language and library semantics supply the meaning of the retained operators and APIs, without their implementation bodies. Each selected operation establishes a fact used above; replacing these lines with callers alone would omit that fact.
