The current question asks: Connect the per-tier usage calculation, basic charge and bill-total accumulation for Suzuki at 120 kWh and Tanaka at 300 kWh. Derive each bill and identify the source decisions that allocate only the excess usage to the higher tier, rather than charging all usage at its highest reached rate. Show how each completed bill then enters the overall total without adding the basic charge a second time.

Answer and source evidence: At 120 kWh, bill=900+120*30=4500. At 300 kWh, bill=900+120*30+180*36=10980. The first tier caps at 120, second tier clamps excess over 120 to 0..180, and third tier uses only positive excess over 300. Each complete bill already contains 900 and is added once to total; no second basic charge is accumulated.

Selection: `main.swift` lines 2, 3, 4, 5, 6. The question supplies both household usages, so literal names/input arrays and print formatting do not help derive the tier decisions or total dependency. Keep the loop binding, bill expression and accumulation initializer/update.

Language/library facts used: Ordinary lexical binding, evaluation order, integer/real arithmetic, and standard output formatting semantics apply.

Minimization: The selected complete lines preserve source order. Each retained declaration, operation, branch or output site supplies an answer fact described above; unrelated input, calculations, other output fields and scaffolding are omitted where not required. Alternative evidence through unrelated callers or complete surrounding functions would add tokens without resolving another answer requirement. The excerpt was reread independently against every clause of the current question.
