package main

import "strings"

type Action struct{ Kind, Argument, Value string }
type Scheduled struct {
	Time, Period int
	Action       Action
}
type Rule struct {
	Tag    string
	Action Action
}
type Program struct {
	Initial   int
	Scheduled []Scheduled
	Rules     []Rule
}
type Process struct {
	Index, Initial, Balance, L         int
	V, B, Next                         []int
	Buffers                            []map[int]*Packet
	Hold                               []*Copy
	Rules                              []Rule
	Events                             []*Event
	Delivered                          []*Copy
	In, Out, Refused, Minimum, MaxHeld int
	Counts                             map[string]int
}

func parseAction(a []string) Action {
	out := Action{Kind: a[0], Argument: a[1]}
	if len(a) > 2 {
		out.Value = a[2]
	}
	return out
}
func readPrograms(network Network) []Program {
	out := make([]Program, len(network.Names))
	current := -1
	for _, line := range readLines("input/programs.txt") {
		a := strings.Fields(line)
		switch a[0] {
		case "PROCESS":
			current = network.Index[a[1]]
			out[current].Initial = integer(a[3])
		case "END":
			current = -1
		case "AT":
			s := Scheduled{Time: integer(a[1])}
			start := 2
			if a[2] == "EVERY" {
				s.Period = integer(a[3])
				start = 4
			}
			s.Action = parseAction(a[start:])
			out[current].Scheduled = append(out[current].Scheduled, s)
		case "ON":
			out[current].Rules = append(out[current].Rules, Rule{a[1], parseAction(a[2:])})
		}
	}
	return out
}
func newProcess(index int, program Program, n int) *Process {
	p := &Process{Index: index, Initial: program.Initial, Balance: program.Initial, V: make([]int, n),
		B: make([]int, n), Next: make([]int, n), Buffers: make([]map[int]*Packet, n), Rules: program.Rules,
		Minimum: program.Initial, Counts: map[string]int{}}
	for i := 0; i < n; i++ {
		p.Next[i] = 1
		p.Buffers[i] = map[int]*Packet{}
	}
	return p
}
func balanceAt(p *Process, count int) int {
	if count == 0 {
		return p.Initial
	}
	return p.Events[count-1].Balance
}
