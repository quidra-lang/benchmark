The current question asks: Suppose only the two result fields are reordered to n: max=M steps=K. Identify where and how the single output-format expression must change, including spaces and the lack of spaces around equals signs. Show which existing values supply M and K; leave their calculations unchanged.

Answer and source evidence: Change only the result-field order in the single output expression: retain the original start label, print max= followed by m/maximum, then one space and steps= followed by k/steps. There are no spaces around either equals sign; the complete pattern is n: max=M steps=K.

Selection: `main.swift` lines 8. The current format expression already identifies every affected literal and supplying value; their calculations need no inspection.

Language/library facts used: Ordinary lexical binding, evaluation order, integer/real arithmetic, and standard output formatting semantics apply.

Minimization: The selected complete lines preserve source order. Each retained declaration, operation, branch or output site supplies an answer fact described above; unrelated input, calculations, other output fields and scaffolding are omitted where not required. Alternative evidence through unrelated callers or complete surrounding functions would add tokens without resolving another answer requirement. The excerpt was reread independently against every clause of the current question.
