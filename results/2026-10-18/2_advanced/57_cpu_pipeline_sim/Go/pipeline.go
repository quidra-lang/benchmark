package main

type Timing struct{ F, D, X, M, W int }
type Stall struct{ Cause, Cycles, Responsible, Waiting, Producer int }
type Run struct {
	Timings        []Timing
	Stalls         []Stall
	Cycles         int
	Totals, Events [4]int
	Refetch        int
}

func simulate(a []Instruction, v Variant, p []Prediction) Run {
	out := Run{Timings: make([]Timing, len(a))}
	for i, ins := range a {
		t := Timing{F: 1, D: 2, X: 3}
		if i > 0 {
			previous := out.Timings[i-1]
			t.F = previous.D
			if p[i-1].Wrong {
				t.F = previous.X
				if !idResolved(a[i-1], v) {
					t.F++
				}
			}
			t.D = max(t.F+1, previous.X)
			bounds := [4]int{t.D + 1, previous.M, previous.X + 1, previous.X + 1}
			producer := [4]int{-1, -1, -1, -1}
			for _, source := range ins.Sources {
				if source.Producer < 0 {
					continue
				}
				cause := 3
				if a[source.Producer].Class == "LOAD" {
					cause = 2
				}
				r := ready(ins, source, a, out.Timings, v)
				if r > bounds[cause] {
					bounds[cause], producer[cause] = r, source.Producer
				}
			}
			current := previous.X + 1
			for cause, b := range bounds {
				if b > current {
					responsible := i
					if cause < 2 {
						responsible = i - 1
					}
					out.Stalls = append(out.Stalls, Stall{cause, b - current, responsible, i, producer[cause]})
					out.Totals[cause] += b - current
					out.Events[cause]++
					current = b
				}
			}
			t.X = current
		}
		e := 1
		if ins.Class == "MUL" {
			e = v.Latency
		}
		t.M, t.W = t.X+e, t.X+e+1
		out.Timings[i] = t
		if p[i].Wrong {
			out.Refetch++
			if !idResolved(ins, v) {
				out.Refetch++
			}
		}
	}
	last := len(a) - 1
	if a[last].Class == "MUL" && v.Latency >= 2 {
		n := v.Latency - 1
		out.Stalls = append(out.Stalls, Stall{1, n, last, -1, -1})
		out.Totals[1] += n
		out.Events[1]++
	}
	out.Cycles = out.Timings[last].W
	return out
}
