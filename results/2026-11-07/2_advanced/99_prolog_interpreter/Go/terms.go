package main

type Term struct {
	Kind, Name string
	Integer    int64
	Arguments  []*Term
	Binding    *Term
}

func atom(name string) *Term { return &Term{Kind: "atom", Name: name} }
func integer(n int64) *Term  { return &Term{Kind: "integer", Integer: n} }
func variable() *Term        { return &Term{Kind: "variable"} }
func compound(name string, args ...*Term) *Term {
	return &Term{Kind: "compound", Name: name, Arguments: args}
}
func dereference(t *Term) *Term {
	for t.Kind == "variable" && t.Binding != nil {
		t = t.Binding
	}
	return t
}
func isCompound(t *Term, name string, arity int) bool {
	t = dereference(t)
	return t.Kind == "compound" && t.Name == name && len(t.Arguments) == arity
}
func isNil(t *Term) bool {
	t = dereference(t)
	return t.Kind == "atom" && t.Name == "[]"
}
func makeList(elements []*Term, tail *Term) *Term {
	if tail == nil {
		tail = atom("[]")
	}
	for i := len(elements) - 1; i >= 0; i-- {
		tail = compound(".", elements[i], tail)
	}
	return tail
}
func listParts(t *Term) ([]*Term, *Term) {
	elements := []*Term{}
	t = dereference(t)
	for isCompound(t, ".", 2) {
		elements = append(elements, t.Arguments[0])
		t = dereference(t.Arguments[1])
	}
	return elements, t
}

type Copier struct{ Variables map[*Term]*Term }

func newCopier() *Copier { return &Copier{Variables: map[*Term]*Term{}} }
func (c *Copier) copy(t *Term) *Term {
	t = dereference(t)
	if t.Kind == "variable" {
		if v := c.Variables[t]; v != nil {
			return v
		}
		v := variable()
		c.Variables[t] = v
		return v
	}
	if t.Kind != "compound" {
		return t
	}
	args := []*Term{}
	for _, arg := range t.Arguments {
		args = append(args, c.copy(arg))
	}
	return compound(t.Name, args...)
}
func copyTerm(t *Term) *Term { return newCopier().copy(t) }
func termVariables(t *Term) []*Term {
	out := []*Term{}
	var walk func(*Term)
	walk = func(t *Term) {
		t = dereference(t)
		if t.Kind == "variable" {
			out = append(out, t)
		} else if t.Kind == "compound" {
			for _, arg := range t.Arguments {
				walk(arg)
			}
		}
	}
	walk(t)
	return out
}

type Indicator struct {
	Name  string
	Arity int
}

func indicator(t *Term) Indicator {
	t = dereference(t)
	if t.Kind == "atom" {
		return Indicator{t.Name, 0}
	}
	return Indicator{t.Name, len(t.Arguments)}
}
func indicatorTerm(p Indicator) *Term { return compound("/", atom(p.Name), integer(int64(p.Arity))) }
func errorTerm(kind string, args ...*Term) *Term {
	if len(args) == 0 {
		return atom(kind)
	}
	return compound(kind, args...)
}
func errorBall(error *Term, p Indicator) *Term { return compound("error", error, indicatorTerm(p)) }
