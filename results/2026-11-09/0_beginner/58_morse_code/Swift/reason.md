The current question asks: Suppose a decoder must accept its Morse text as the only message input and must match complete code tokens exactly, never a prefix. Explain where and how its word splitting, letter-token splitting, reverse lookup and result joining must agree so . maps to E and .- maps to A independently and word spaces are restored. Cite the existing stages and identify which already meet the requirement; do not change the Morse table or use original-message letters as a fallback.

Answer and source evidence: The decoder already uses encoded alone, splitting words at " / " then complete letter tokens at space, and performing exact equality/index/dictionary lookup rather than prefix matching. The unchanged table maps . to E and .- to A independently. Concatenating decoded letters within each word and joining words with one ASCII space restores word boundaries. No original-message fallback is needed.

Selection: `main.swift` lines 3, 4, 6, 11, 12, 13. Retain table/key association and every decoder stage; encoder and original message are unnecessary because only its already-generated Morse input is relevant.

Language/library facts used: Ordinary lexical binding, evaluation order, integer/real arithmetic, and standard output formatting semantics apply.

Minimization: The selected complete lines preserve source order. Each retained declaration, operation, branch or output site supplies an answer fact described above; unrelated input, calculations, other output fields and scaffolding are omitted where not required. Alternative evidence through unrelated callers or complete surrounding functions would add tokens without resolving another answer requirement. The excerpt was reread independently against every clause of the current question.
