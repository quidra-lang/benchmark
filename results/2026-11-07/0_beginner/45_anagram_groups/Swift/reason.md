The current question asks: For apple's anagram signature, locate the lookup, condition or default-creation operation that chooses a new group rather than an existing one. Explain the decision from the source's actual key representation and absent-key behavior. Focus on this one group-selection decision; do not trace all words or output ordering.

Answer and source evidence: The signature for apple is sorted letters aelpp. Swift tests dictionary absence with groups[key]==nil and default [] creates that group before append. Go/Rust do not perform a key lookup: a still-unused outer position starts a fresh group, and the inner scan appends unused words with equal sorted-byte signatures, marking them used. Thus apple starts its own group when reached.

Selection: `main.swift` lines 1, 6, 7, 8, 9. The representation and actual absence/unused decision are retained; input ordering, all other words and rendering are outside this local decision. The word loop binding links the signature and absent-key update to the same incoming word.

Language/library facts used: Ordinary lexical binding, evaluation order, integer/real arithmetic, and standard output formatting semantics apply.

Minimization: The selected complete lines preserve source order. Each retained declaration, operation, branch or output site supplies an answer fact described above; unrelated input, calculations, other output fields and scaffolding are omitted where not required. Alternative evidence through unrelated callers or complete surrounding functions would add tokens without resolving another answer requirement. The excerpt was reread independently against every clause of the current question.
