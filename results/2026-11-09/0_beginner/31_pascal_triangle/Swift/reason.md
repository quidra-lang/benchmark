The current question asks: Locate the block that constructs row 1 from row 0 and distinguish endpoint handling from interior addition. Explain how the single initial value and two row-1 endpoints are supplied, and identify the condition, range or construction that prevents reading nonexistent neighboring entries of the preceding row. Do not derive a whole later row.

Answer and source evidence: Row 0 begins with one 1. Go/Rust retain a fixed zero-filled row with row[0]=1 and descend k from n to 1, so at n=1 row[1]=0+1 and row[0] stays 1; k>0 prevents reading row[-1]. Swift builds a next array of two 1 endpoints and its interior range 1..<row.count is empty for row.count=1, so no nonexistent neighbors are read. Row 1 is therefore 1 1.

Selection: `main.swift` lines 1, 4, 5, 6. Initial row representation, the row-1 update bounds and endpoint/interior construction suffice; output conversion and later rows are outside scope.

Language/library facts used: Ordinary lexical binding, evaluation order, integer/real arithmetic, and standard output formatting semantics apply.

Minimization: The selected complete lines preserve source order. Each retained declaration, operation, branch or output site supplies an answer fact described above; unrelated input, calculations, other output fields and scaffolding are omitted where not required. Alternative evidence through unrelated callers or complete surrounding functions would add tokens without resolving another answer requirement. The excerpt was reread independently against every clause of the current question.
