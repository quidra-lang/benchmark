package main

type Production struct {
	Number   int
	LHS      string
	RHS      []string
	Notation string
	Predict  map[string]string
}
type CellKey struct{ LHS, Token string }
type TableEntry struct {
	Number int
	Reason string
}
type Conflict struct {
	LHS, Token, Kind string
	Entries          []TableEntry
	Chosen           int
}
type ParseTable struct {
	Productions []Production
	Cells       map[CellKey][]TableEntry
	Choices     map[CellKey]int
	Conflicts   []Conflict
}

func numberProductions(g Grammar) []Production {
	out := []Production{}
	for _, lhs := range g.Order {
		for _, rhs := range g.Rules[lhs] {
			out = append(out, Production{Number: len(out) + 1, LHS: lhs, RHS: rhs, Notation: productionNotation(lhs, rhs)})
		}
	}
	return out
}
func buildTable(g Grammar, sets Sets) ParseTable {
	table := ParseTable{Productions: numberProductions(g), Cells: map[CellKey][]TableEntry{}, Choices: map[CellKey]int{}}
	for i, p := range table.Productions {
		direct, empty := firstSequence(p.RHS, sets.Nullable, sets.First)
		predict := map[string]string{}
		for t := range direct {
			predict[t] = "FIRST"
		}
		if empty {
			for t := range sets.Follow[p.LHS] {
				if predict[t] == "" {
					predict[t] = "FOLLOW"
				}
			}
		}
		table.Productions[i].Predict = predict
		for token, reason := range predict {
			key := CellKey{p.LHS, token}
			table.Cells[key] = append(table.Cells[key], TableEntry{p.Number, reason})
		}
	}
	for _, lhs := range g.Order {
		for _, token := range append(append([]string{}, sets.Terminals...), "$") {
			key := CellKey{lhs, token}
			entries := table.Cells[key]
			if len(entries) == 0 {
				continue
			}
			chosen := entries[0].Number
			hasFirst, hasFollow := false, false
			for _, entry := range entries {
				if entry.Reason == "FIRST" {
					if !hasFirst {
						chosen = entry.Number
					}
					hasFirst = true
				} else {
					hasFollow = true
				}
			}
			table.Choices[key] = chosen
			if len(entries) > 1 {
				kind := "FIRST/FOLLOW"
				if !hasFirst {
					kind = "FOLLOW/FOLLOW"
				}
				if !hasFollow {
					kind = "FIRST/FIRST"
				}
				table.Conflicts = append(table.Conflicts, Conflict{lhs, token, kind, entries, chosen})
			}
		}
	}
	return table
}
