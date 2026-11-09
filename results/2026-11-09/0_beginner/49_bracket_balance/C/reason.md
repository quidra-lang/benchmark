The recognition branches accept only opening `([{` or closing `)]}` characters. A plus sign matches neither, so it performs no stack action. The source scans the original string directly and advances its original zero-based position i for every character; plus in `(a + b) * [c - d]` is at index 3 and still occupies that position. Error positions use that same i. No prefilter or renumbered token stream intervenes; stack-match internals are unnecessary for this recognition decision.



The excerpt preserves complete source lines in their source order. Only the named inputs, decisions, updates and output operations needed for this question are retained; unrelated calculations, entry-point scaffolding and unused output are omitted. Standard language and library semantics supply the meaning of the retained operators and APIs, without their implementation bodies. Each selected operation establishes a fact used above; replacing these lines with callers alone would omit that fact.
