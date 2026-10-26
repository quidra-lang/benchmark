package main

type GridState struct {
	Letters []byte
	Words   []int
	Used    []bool
}

func newGridState(letters []byte, count, wordCount int) GridState {
	state := GridState{append([]byte(nil), letters...), make([]int, count), make([]bool, wordCount)}
	for i := range state.Words {
		state.Words[i] = -1
	}
	return state
}

func (state GridState) Copy() GridState {
	return GridState{append([]byte(nil), state.Letters...), append([]int(nil), state.Words...), append([]bool(nil), state.Used...)}
}
func (state GridState) Pattern(slot Slot) []byte {
	pattern := make([]byte, slot.Length())
	for position, cell := range slot.Cells {
		pattern[position] = state.Letters[cell]
	}
	return pattern
}

func (state *GridState) Assign(slot Slot, id int, index *WordIndex) []int {
	var changed []int
	for position, cell := range slot.Cells {
		if state.Letters[cell] == '.' {
			state.Letters[cell] = index.Words[id].Letters[position]
			changed = append(changed, cell)
		}
	}
	state.Words[slot.Index] = id
	state.Used[id] = true
	return changed
}

func (state *GridState) Unassign(slot Slot, changed []int) {
	for _, cell := range changed {
		state.Letters[cell] = '.'
	}
	state.Used[state.Words[slot.Index]] = false
	state.Words[slot.Index] = -1
}

type Attempt struct {
	Layout                                                         *Layout
	Index                                                          *WordIndex
	State, Best                                                    GridState
	Minimum, Budget, Nodes, Backtracks, Prunes, DeadEnds, MaxDepth int
	Sequence, Failures                                             []int
	Trace                                                          []string
	Outcome                                                        string
}

func newAttempt(layout *Layout, index *WordIndex, initial GridState, minimum, budget int) *Attempt {
	return &Attempt{Layout: layout, Index: index, State: initial.Copy(), Best: initial.Copy(), Minimum: minimum, Budget: budget, Failures: make([]int, len(layout.Slots))}
}

func (a *Attempt) Run() {
	switch a.search() {
	case "complete":
		a.Outcome = "filled"
	case "abort":
		a.Outcome = "budget"
	default:
		a.Outcome = "unfillable"
	}
}
func (a *Attempt) FinalState() GridState {
	if a.Outcome == "filled" {
		return a.State
	}
	return a.Best
}
func (a *Attempt) candidates(slot Slot) []int {
	return a.Index.Candidates(a.State.Pattern(slot), a.Minimum, a.State.Used)
}

func (a *Attempt) search() string {
	chosen := -1
	var choices []int
	for _, slot := range a.Layout.Slots {
		if a.State.Words[slot.Index] >= 0 {
			continue
		}
		available := a.candidates(slot)
		if chosen < 0 || len(available) < len(choices) {
			chosen, choices = slot.Index, available
		}
	}
	if chosen < 0 {
		return "complete"
	}
	if len(choices) == 0 {
		a.DeadEnds++
		a.Failures[chosen]++
		return "fail"
	}
	slot := a.Layout.Slots[chosen]
	for _, word := range choices {
		if a.Nodes == a.Budget {
			return "abort"
		}
		a.Nodes++
		changed := a.State.Assign(slot, word, a.Index)
		a.Sequence = append(a.Sequence, chosen)
		wiped := -1
		for _, other := range slot.Crossings {
			if a.State.Words[other] < 0 && len(a.candidates(a.Layout.Slots[other])) == 0 {
				wiped = other
				break
			}
		}
		if a.Nodes <= 10 {
			mark := ""
			if wiped >= 0 {
				mark = "!"
			}
			a.Trace = append(a.Trace, slot.Label+"="+a.Index.Words[word].Text+mark)
		}
		result := "fail"
		if wiped >= 0 {
			a.Prunes++
			a.Failures[wiped]++
		} else {
			if len(a.Sequence) > a.MaxDepth {
				a.MaxDepth = len(a.Sequence)
				a.Best = a.State.Copy()
			}
			result = a.search()
		}
		if result != "fail" {
			return result
		}
		a.State.Unassign(slot, changed)
		a.Sequence = a.Sequence[:len(a.Sequence)-1]
		a.Backtracks++
	}
	return "fail"
}
