package main

type Concurrency struct {
	Pairs, Ordered, Concurrent, SameLamport, Inversions int
	Processes                                           map[[2]int]int
}

func graph(sim *Simulation) [][]int {
	out := make([][]int, len(sim.Events))
	for _, p := range sim.Processes {
		for i := 0; i+1 < len(p.Events); i++ {
			e, f := p.Events[i], p.Events[i+1]
			out[e.Number-1] = append(out[e.Number-1], f.Number-1)
		}
	}
	for _, c := range sim.Copies {
		if c.Received != nil {
			e, f := c.Message.Event, c.Received
			out[e.Number-1] = append(out[e.Number-1], f.Number-1)
		}
	}
	return out
}
func path(edges [][]int, start, end int) []int {
	parents := make([]int, len(edges))
	for i := range parents {
		parents[i] = -1
	}
	parents[start] = start
	queue := []int{start}
	for head := 0; head < len(queue) && parents[end] < 0; head++ {
		e := queue[head]
		for _, f := range edges[e] {
			if parents[f] < 0 {
				parents[f] = e
				queue = append(queue, f)
				if f == end {
					break
				}
			}
		}
	}
	if parents[end] < 0 {
		return nil
	}
	out := []int{}
	for f := end; ; f = parents[f] {
		out = append(out, f)
		if f == start {
			break
		}
	}
	for i, j := 0, len(out)-1; i < j; i, j = i+1, j-1 {
		out[i], out[j] = out[j], out[i]
	}
	return out
}
func concurrency(events []*Event) Concurrency {
	out := Concurrency{Processes: map[[2]int]int{}}
	for i, a := range events {
		for _, b := range events[i+1:] {
			out.Pairs++
			if relation(a.V, b.V) == "||" {
				out.Concurrent++
				if a.L == b.L {
					out.SameLamport++
				}
				p, q := a.Process, b.Process
				if p > q {
					p, q = q, p
				}
				out.Processes[[2]int{p, q}]++
			} else {
				out.Ordered++
			}
			if (a.Time < b.Time && a.L > b.L) || (a.Time > b.Time && a.L < b.L) {
				out.Inversions++
			}
		}
	}
	return out
}
func races(p *Process) [][2]*Copy {
	out := [][2]*Copy{}
	for i := 0; i+1 < len(p.Delivered); i++ {
		a, b := p.Delivered[i], p.Delivered[i+1]
		if relation(a.Message.Event.V, b.Message.Event.V) == "||" {
			out = append(out, [2]*Copy{a, b})
		}
	}
	return out
}
func violations(sim *Simulation) ([][3]int, int) {
	out := [][3]int{}
	fifo := 0
	for p, state := range sim.Processes {
		for i, a := range state.Delivered {
			for j := i + 1; j < len(state.Delivered); j++ {
				b := state.Delivered[j]
				if relation(b.Message.Event.V, a.Message.Event.V) == "->" {
					out = append(out, [3]int{p, i, j})
					if a.Source == b.Source {
						fifo++
					}
				}
			}
		}
	}
	return out, fifo
}

type EnumeratedCuts struct {
	Limits              []int
	Product, Consistent int
	Levels              []int
	Amounts             []int
	Valid               []bool
	Strides             []int
}

func enumerate(sim *Simulation, time int) EnumeratedCuts {
	n := len(sim.Processes)
	out := EnumeratedCuts{Limits: make([]int, n), Strides: make([]int, n), Product: 1}
	levelMax := 0
	for p, state := range sim.Processes {
		for _, e := range state.Events {
			if e.Time <= time {
				out.Limits[p]++
			}
		}
		levelMax += out.Limits[p]
	}
	for p := n - 1; p >= 0; p-- {
		out.Strides[p] = out.Product
		out.Product *= out.Limits[p] + 1
	}
	out.Levels = make([]int, levelMax+1)
	out.Amounts = make([]int, out.Product)
	out.Valid = make([]bool, out.Product)
	for index := 0; index < out.Product; index++ {
		cut := make([]int, n)
		level, balance := 0, 0
		for p := 0; p < n; p++ {
			cut[p] = (index / out.Strides[p]) % (out.Limits[p] + 1)
			level += cut[p]
			balance += balanceAt(sim.Processes[p], cut[p])
		}
		valid := true
		for p, count := range cut {
			if count > 0 && !lessEqual(sim.Processes[p].Events[count-1].V, cut) {
				valid = false
				break
			}
		}
		if valid {
			out.Valid[index] = true
			out.Consistent++
			out.Levels[level]++
			out.Amounts[index] = sim.Initial - balance
		}
	}
	return out
}
func (e EnumeratedCuts) predicate(threshold int) (int, bool) {
	count := 0
	safe := make([]bool, e.Product)
	for index := 0; index < e.Product; index++ {
		if !e.Valid[index] {
			continue
		}
		if e.Amounts[index] >= threshold {
			count++
			continue
		}
		if index == 0 {
			safe[index] = true
			continue
		}
		for p, stride := range e.Strides {
			component := (index / stride) % (e.Limits[p] + 1)
			if component > 0 && safe[index-stride] {
				safe[index] = true
				break
			}
		}
	}
	return count, !safe[e.Product-1]
}
