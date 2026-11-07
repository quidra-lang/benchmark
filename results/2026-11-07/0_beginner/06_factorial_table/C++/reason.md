Rename the local binding `n` to `term_number` and every reference to it in the loop boundary, advancement, positive-term guard, factorial multiplication and output argument. The literal `! = ` and the factorial accumulator name remain unchanged. There is no independently scoped factorial-call parameter in this implementation, so no second binding requires renaming.



The excerpt preserves complete source lines in their source order. Only the named inputs, decisions, updates and output operations needed for this question are retained; unrelated calculations, entry-point scaffolding and unused output are omitted. Standard language and library semantics supply the meaning of the retained operators and APIs, without their implementation bodies. Each selected operation establishes a fact used above; replacing these lines with callers alone would omit that fact.
