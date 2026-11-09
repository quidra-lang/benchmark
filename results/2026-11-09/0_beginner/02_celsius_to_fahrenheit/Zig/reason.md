The array loop binds `celsius` to -3; `@floatFromInt` in f64 context preserves fractional Fahrenheit arithmetic, giving `fahrenheit = 26.6`. The two print arguments resolve to this iteration binding and its computed local result. `{d:.1}` formats the latter, producing `-3 C = 26.6 F` and LF.



The excerpt preserves complete source lines in their source order. Only the named inputs, decisions, updates and output operations needed for this question are retained; unrelated calculations, entry-point scaffolding and unused output are omitted. Standard language and library semantics supply the meaning of the retained operators and APIs, without their implementation bodies. Each selected operation establishes a fact used above; replacing these lines with callers alone would omit that fact.
