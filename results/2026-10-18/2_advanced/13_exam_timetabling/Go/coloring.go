package main

type Choice struct {
	course     string
	saturation int
}
type Attempt struct {
	courses        []string
	graph          *ConflictGraph
	limit          int
	candidateSlots func(string, map[string]int) []int
	deadEnds       int
	deadEndCourse  string
	aborted        bool
	chosen         []Choice
}

func (a *Attempt) saturation(id string, assignment map[string]int) int {
	slots := map[int]bool{}
	for neighbour := range a.graph.neighbours(id) {
		if slot, assigned := assignment[neighbour]; assigned {
			slots[slot] = true
		}
	}
	return len(slots)
}
func (a *Attempt) search(assignment map[string]int) bool {
	chosen := ""
	saturation, degree := -1, -1
	for _, id := range a.courses {
		if _, assigned := assignment[id]; assigned {
			continue
		}
		sat, deg := a.saturation(id, assignment), a.graph.degree(id)
		if chosen == "" || sat > saturation || sat == saturation && (deg > degree || deg == degree && id < chosen) {
			chosen, saturation, degree = id, sat, deg
		}
	}
	if chosen == "" {
		return true
	}
	a.chosen = append(a.chosen, Choice{chosen, saturation})
	for _, slot := range a.candidateSlots(chosen, assignment) {
		assignment[chosen] = slot
		if a.search(assignment) {
			return true
		}
		delete(assignment, chosen)
		if a.aborted {
			return false
		}
	}
	a.chosen = a.chosen[:len(a.chosen)-1]
	a.deadEnds++
	a.deadEndCourse = chosen
	a.aborted = a.deadEnds > a.limit
	return false
}
func greedyNumbering(order []string, graph *ConflictGraph) int {
	numbers := map[string]int{}
	largest := 0
	for _, id := range order {
		taken := map[int]bool{}
		for neighbour := range graph.neighbours(id) {
			if number, exists := numbers[neighbour]; exists {
				taken[number] = true
			}
		}
		number := 1
		for taken[number] {
			number++
		}
		numbers[id] = number
		largest = max(largest, number)
	}
	return largest
}
