package main

import "sort"

type NumberedClause struct {
	Number   int
	Literals []int
}
type Preparation struct {
	Clauses     [][]int
	Fixed       map[int]bool
	Active      []int
	Counts      map[string]int
	Records     map[string][]int
	EmptyClause int
	Pure        bool
}

func preprocess(f Formula, usePure bool) *Preparation {
	p := &Preparation{Fixed: map[int]bool{}, Counts: map[string]int{}, Records: map[string][]int{}, Pure: usePure}
	working := []NumberedClause{}
	for i, clause := range f.Clauses {
		present := map[int]bool{}
		for _, lit := range clause {
			present[lit] = true
		}
		tautology := false
		for _, lit := range clause {
			if present[-lit] {
				tautology = true
				break
			}
		}
		if tautology {
			p.Counts["tautologies"]++
			p.Records["tautology"] = append(p.Records["tautology"], i+1)
			continue
		}
		seen := map[int]bool{}
		reduced := []int{}
		for _, lit := range clause {
			if seen[lit] {
				p.Counts["duplicate_literals"]++
			} else {
				seen[lit] = true
				reduced = append(reduced, lit)
			}
		}
		working = append(working, NumberedClause{i + 1, reduced})
	}
	for {
		unit := 0
		for _, c := range working {
			if len(c.Literals) == 0 {
				p.EmptyClause = c.Number
				break
			}
		}
		if p.EmptyClause > 0 {
			break
		}
		for _, c := range working {
			if len(c.Literals) == 1 {
				unit = c.Literals[0]
				break
			}
		}
		if unit == 0 {
			break
		}
		p.Fixed[abs(unit)] = unit > 0
		p.Counts["unit_fixed"]++
		surviving := []NumberedClause{}
		for _, c := range working {
			if contains(c.Literals, unit) {
				p.Records["unit"] = append(p.Records["unit"], c.Number)
				p.Counts["unit_removed"]++
			} else {
				lits := []int{}
				for _, lit := range c.Literals {
					if lit != -unit {
						lits = append(lits, lit)
					}
				}
				surviving = append(surviving, NumberedClause{c.Number, lits})
			}
		}
		working = surviving
	}
	if p.EmptyClause == 0 {
		remove := make([]bool, len(working))
		sets := make([]map[int]bool, len(working))
		for i, c := range working {
			sets[i] = map[int]bool{}
			for _, lit := range c.Literals {
				sets[i][lit] = true
			}
		}
		for bi, b := range working {
			for ai, a := range working {
				if ai == bi || !(len(a.Literals) < len(b.Literals) || ai < bi) {
					continue
				}
				subset := true
				for _, lit := range a.Literals {
					if !sets[bi][lit] {
						subset = false
						break
					}
				}
				if subset {
					remove[bi] = true
					break
				}
			}
		}
		surviving := []NumberedClause{}
		for i, c := range working {
			if remove[i] {
				p.Records["subsumed"] = append(p.Records["subsumed"], c.Number)
				p.Counts["subsumed"]++
			} else {
				surviving = append(surviving, c)
			}
		}
		working = surviving
		if usePure {
			for {
				present := map[int]bool{}
				for _, c := range working {
					for _, lit := range c.Literals {
						present[lit] = true
					}
				}
				pure := map[int]bool{}
				for lit := range present {
					if !present[-lit] {
						pure[lit] = true
					}
				}
				if len(pure) == 0 {
					break
				}
				for lit := range pure {
					p.Fixed[abs(lit)] = lit > 0
				}
				p.Counts["pure_fixed"] += len(pure)
				remaining := []NumberedClause{}
				for _, c := range working {
					removed := false
					for _, lit := range c.Literals {
						if pure[lit] {
							removed = true
							break
						}
					}
					if removed {
						p.Records["pure"] = append(p.Records["pure"], c.Number)
						p.Counts["pure_removed"]++
					} else {
						remaining = append(remaining, c)
					}
				}
				working = remaining
			}
		}
	}
	for _, name := range []string{"tautologies", "unit_removed", "subsumed", "pure_removed"} {
		p.Counts["removed"] += p.Counts[name]
	}
	for _, c := range working {
		p.Clauses = append(p.Clauses, c.Literals)
	}
	for v := 1; v <= f.Variables; v++ {
		if _, fixed := p.Fixed[v]; !fixed {
			p.Active = append(p.Active, v)
		}
	}
	for _, records := range p.Records {
		sort.Ints(records)
	}
	return p
}
