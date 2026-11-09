# Task B: 94_league_standings / Julia

The standings order must have its own ordering storage if the original sequence must remain available. Sharing unchanged team records between those two order containers is safe; sharing/reordering the container itself loses the original sequence. Inspect the sort operation rather than recomputing statistics.

sort!(teams;by=...) reorders the existing team vector in place. Use a separately sorted vector (sort(teams;by=...)) for standings; its team records can remain shared because sorting only changes container order.

Evidence is from `main.jl`, L4,L5,L42,L43,L44,L45,L46,L47,L48,L49,L50.

- L4: `teams = ["Lions", "Tigers", "Eagles", "Sharks", "Wolves", "Bears"]`
- L5: `records = Dict(team=>zeros(Int, 7) for team in teams)`
- L42: `sort!(`
- L43: `teams;`
- L44: `by = team -> (`
- L45: `-records[team][7],`
- L46: `-(records[team][5]-records[team][6]),`
- L47: `-records[team][5],`
- L48: `team,`
- L49: `),`
- L50: `)`

Minimization: The original ordering binding and actual standings sort are sufficient to distinguish order storage from record sharing. Score updates and table rendering are outside this expression-level question. The selected complete original lines, in source order, cost 147 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 595, and the complete source costs 824. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
