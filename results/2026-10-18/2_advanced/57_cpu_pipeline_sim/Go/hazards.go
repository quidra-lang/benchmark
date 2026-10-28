package main

type Source struct{ Register, Producer int }
type Instruction struct {
	PC                    int
	Class                 string
	RD, RS1, RS2          int
	Taken                 bool
	Target, Address, Line int
	Sources               []Source
}

func (i Instruction) control() bool { return i.Class == "BRANCH" || i.Class == "JUMP" }
func (i Instruction) nextPC() int {
	if i.Taken {
		return i.Target
	}
	return i.PC + 4
}
func dependences(a []Instruction) {
	last := [32]int{}
	for r := range last {
		last[r] = -1
	}
	for i := range a {
		for _, r := range []int{a[i].RS1, a[i].RS2} {
			if r > 0 {
				a[i].Sources = append(a[i].Sources, Source{r, last[r]})
			}
		}
		if a[i].RD > 0 {
			last[a[i].RD] = i
		}
	}
}
func idResolved(i Instruction, v Variant) bool {
	return i.control() && (v.Stage == "ID" || (i.Class == "JUMP" && i.RS1 < 0))
}
func ready(i Instruction, source Source, a []Instruction, t []Timing, v Variant) int {
	p := source.Producer
	if !v.Forward {
		return t[p].W + 1
	}
	r := t[p].M
	if a[p].Class == "LOAD" {
		r = t[p].W
	}
	if idResolved(i, v) {
		r++
	}
	return r
}
func forwardingPath(index int, i Instruction, source Source, t []Timing, v Variant) int {
	if !v.Forward || source.Producer < 0 {
		return 0
	}
	u := t[index].X
	resolved := idResolved(i, v)
	if resolved {
		u--
	}
	p := t[source.Producer]
	if p.M == u {
		return 1
	}
	if !resolved && p.W == u {
		return 2
	}
	return 0
}
