The current question asks: Explain the complete run from the fifteen stored integers through duplicate detection, retained-value ordering and the two final output lines. Trace the three occurrences of 12 as a concrete example, then derive the retained sequence and removed count. Identify the source operations that distinguish a repeated value from a new value, preserve first appearance and construct each output line.

Answer and source evidence: The 12 at indices 0,2,13 is appended on its first appearance; the later two are already seen/contained and are skipped. New values are appended or admitted by an order-preserving filter, so the retained sequence is 12 5 8 3 20 15 7 9. Fifteen inputs minus eight retained values gives the second line removed: 7. The selected output operations show one space between values and exactly those two lines.

Selection: `main.swift` lines 1, 2, 3, 4, 5. Every collection, duplicate decision, order-preserving append/filter and output construction contributes to the complete run. Only wrapper declarations are omitted.

Language/library facts used: Ordinary lexical binding, evaluation order, integer/real arithmetic, and standard output formatting semantics apply.

Minimization: The selected complete lines preserve source order. Each retained declaration, operation, branch or output site supplies an answer fact described above; unrelated input, calculations, other output fields and scaffolding are omitted where not required. Alternative evidence through unrelated callers or complete surrounding functions would add tokens without resolving another answer requirement. The excerpt was reread independently against every clause of the current question.
