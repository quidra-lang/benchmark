Starting (48,180), successive remainders are 48,36,12,0. Each iteration shifts b into a and r into b; when b becomes zero the guard ends the loop and returns a=12. The signed `int` working values admit zero; there is no runtime or type-level positive-only check, and positivity here follows from these inputs and arithmetic. The gcd body establishes this operation directly; caller data and lcm/output calculations add nothing because the question supplies the arguments.



The excerpt preserves complete source lines in their source order. Only the named inputs, decisions, updates and output operations needed for this question are retained; unrelated calculations, entry-point scaffolding and unused output are omitted. Standard language and library semantics supply the meaning of the retained operators and APIs, without their implementation bodies. Each selected operation establishes a fact used above; replacing these lines with callers alone would omit that fact.
