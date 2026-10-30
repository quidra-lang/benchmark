package main

type Bindings struct{ Trail []*Term }

func (b *Bindings) mark() int { return len(b.Trail) }
func (b *Bindings) undo(mark int) {
	for len(b.Trail) > mark {
		last := b.Trail[len(b.Trail)-1]
		last.Binding = nil
		b.Trail = b.Trail[:len(b.Trail)-1]
	}
}
func (b *Bindings) bind(v, t *Term) {
	v.Binding = t
	b.Trail = append(b.Trail, v)
}
func (b *Bindings) unify(a, c *Term) bool {
	pairs := [][2]*Term{{a, c}}
	for len(pairs) > 0 {
		pair := pairs[len(pairs)-1]
		pairs = pairs[:len(pairs)-1]
		x, y := dereference(pair[0]), dereference(pair[1])
		if x == y {
			continue
		}
		if x.Kind == "variable" {
			b.bind(x, y)
			continue
		}
		if y.Kind == "variable" {
			b.bind(y, x)
			continue
		}
		if x.Kind != y.Kind {
			return false
		}
		switch x.Kind {
		case "integer":
			if x.Integer != y.Integer {
				return false
			}
		case "atom":
			if x.Name != y.Name {
				return false
			}
		case "compound":
			if x.Name != y.Name || len(x.Arguments) != len(y.Arguments) {
				return false
			}
			for i := len(x.Arguments) - 1; i >= 0; i-- {
				pairs = append(pairs, [2]*Term{x.Arguments[i], y.Arguments[i]})
			}
		}
	}
	return true
}
func identical(a, b *Term) bool {
	pairs := [][2]*Term{{a, b}}
	for len(pairs) > 0 {
		pair := pairs[len(pairs)-1]
		pairs = pairs[:len(pairs)-1]
		x, y := dereference(pair[0]), dereference(pair[1])
		if x == y {
			continue
		}
		if x.Kind != y.Kind {
			return false
		}
		switch x.Kind {
		case "variable":
			return false
		case "integer":
			if x.Integer != y.Integer {
				return false
			}
		case "atom":
			if x.Name != y.Name {
				return false
			}
		case "compound":
			if x.Name != y.Name || len(x.Arguments) != len(y.Arguments) {
				return false
			}
			for i := len(x.Arguments) - 1; i >= 0; i-- {
				pairs = append(pairs, [2]*Term{x.Arguments[i], y.Arguments[i]})
			}
		}
	}
	return true
}
