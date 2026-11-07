package main

type Drop struct {
	Pick     *Pick
	Residual float64
}
type LocationPass struct {
	Picks []*Pick
	Run   LocationRun
}
type Candidate struct {
	Number   int
	First    *Pick
	Picks    []*Pick
	Passes   []LocationPass
	Dropped  []Drop
	Event    int
	Rejected bool
}

func associate(picks []*Pick, window, minimum int) []*Candidate {
	out := []*Candidate{}
	for i, first := range picks {
		if first.Assigned {
			continue
		}
		chosen := []*Pick{}
		seen := map[int]bool{}
		for _, pick := range picks[i:] {
			if pick.Sample > first.Sample+window {
				break
			}
			station := pick.Station.Order
			if pick.Assigned || seen[station] {
				continue
			}
			chosen = append(chosen, pick)
			seen[station] = true
		}
		if len(chosen) < minimum {
			continue
		}
		for _, pick := range chosen {
			pick.Assigned = true
		}
		out = append(out, &Candidate{Number: len(out) + 1, First: first, Picks: chosen})
	}
	return out
}
