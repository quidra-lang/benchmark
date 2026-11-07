The exact integer operands are `total` (sum of token lengths) and `count` (number of tokens). `(double)total / count` already converts before division, so the usual arithmetic conversions produce a real quotient instead of integer truncation. Preserve that pre-division conversion when porting; converting the completed integer quotient would lose the fraction. The accumulation lines establish the operands without unrelated longest/shortest logic.



The excerpt preserves complete source lines in their source order. Only the named inputs, decisions, updates and output operations needed for this question are retained; unrelated calculations, entry-point scaffolding and unused output are omitted. Standard language and library semantics supply the meaning of the retained operators and APIs, without their implementation bodies. Each selected operation establishes a fact used above; replacing these lines with callers alone would omit that fact.
