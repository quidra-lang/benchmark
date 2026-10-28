package main

type BTB struct {
	PC, Target []int
	Valid      []bool
}

func newBTB(n int) *BTB { return &BTB{make([]int, n), make([]int, n), make([]bool, n)} }
func (b *BTB) lookup(pc int) (int, bool) {
	i := (pc / 4) % len(b.PC)
	return b.Target[i], b.Valid[i] && b.PC[i] == pc
}
func (b *BTB) insert(pc, target int) {
	i := (pc / 4) % len(b.PC)
	b.PC[i], b.Target[i], b.Valid[i] = pc, target, true
}

type RAS struct {
	Depth int
	Stack []int
}

func (r *RAS) push(v int) {
	if r.Depth == 0 {
		return
	}
	if len(r.Stack) == r.Depth {
		r.Stack = r.Stack[1:]
	}
	r.Stack = append(r.Stack, v)
}
func (r *RAS) pop() (int, bool) {
	if len(r.Stack) == 0 {
		return 0, false
	}
	v := r.Stack[len(r.Stack)-1]
	r.Stack = r.Stack[:len(r.Stack)-1]
	return v, true
}

type Direction struct {
	Config                 PredictorConfig
	Local, Global, Chooser []int
	History                int
}

func filled(n, v int) []int {
	a := make([]int, n)
	for i := range a {
		a[i] = v
	}
	return a
}
func newDirection(c PredictorConfig) *Direction {
	d := &Direction{Config: c}
	p := c.Parameters
	switch c.Scheme {
	case "ONEBIT":
		d.Local = filled(p[0], 0)
	case "TWOBIT":
		d.Local = filled(p[0], 1)
	case "GSHARE":
		d.Global = filled(p[0], 1)
	case "TOURNAMENT":
		d.Local, d.Global, d.Chooser = filled(p[0], 1), filled(p[1], 1), filled(p[3], 1)
	}
	return d
}
func (d *Direction) predict(i Instruction) bool {
	pc := i.PC / 4
	switch d.Config.Scheme {
	case "BTFN":
		return i.Target < i.PC
	case "ONEBIT":
		return d.Local[pc%len(d.Local)] == 1
	case "TWOBIT":
		return d.Local[pc%len(d.Local)] >= 2
	case "GSHARE":
		return d.Global[(pc^d.History)%len(d.Global)] >= 2
	case "TOURNAMENT":
		if d.Chooser[pc%len(d.Chooser)] >= 2 {
			return d.Global[(pc^d.History)%len(d.Global)] >= 2
		}
		return d.Local[pc%len(d.Local)] >= 2
	}
	return false
}
func counter(v int, taken bool) int {
	if taken {
		return min(3, v+1)
	}
	return max(0, v-1)
}
func (d *Direction) update(i Instruction) {
	pc := i.PC / 4
	p := d.Config.Parameters
	switch d.Config.Scheme {
	case "ONEBIT":
		v := 0
		if i.Taken {
			v = 1
		}
		d.Local[pc%len(d.Local)] = v
	case "TWOBIT":
		k := pc % len(d.Local)
		d.Local[k] = counter(d.Local[k], i.Taken)
	case "GSHARE", "TOURNAMENT":
		k := (pc ^ d.History) % len(d.Global)
		h := p[1]
		if d.Config.Scheme == "TOURNAMENT" {
			local, chooser := pc%len(d.Local), pc%len(d.Chooser)
			lp, gp := d.Local[local] >= 2, d.Global[k] >= 2
			if lp != gp {
				d.Chooser[chooser] = counter(d.Chooser[chooser], gp == i.Taken)
			}
			d.Local[local] = counter(d.Local[local], i.Taken)
			h = p[2]
		}
		d.Global[k] = counter(d.Global[k], i.Taken)
		bit := 0
		if i.Taken {
			bit = 1
		}
		d.History = (2*d.History + bit) % (1 << h)
	}
}
func storage(p PredictorConfig) int {
	a := p.Parameters
	switch p.Scheme {
	case "ONEBIT":
		return a[0]
	case "TWOBIT":
		return 2 * a[0]
	case "GSHARE":
		return 2*a[0] + a[1]
	case "TOURNAMENT":
		return 2*(a[0]+a[1]+a[3]) + a[2]
	}
	return 0
}
