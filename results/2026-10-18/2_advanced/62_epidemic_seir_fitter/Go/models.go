package main

type Model struct {
	Kind                            string
	Beta, Gamma, Sigma, N, Fatality float64
	Groups                          []Group
	W                               [][]float64
}

func (m Model) rate(y []float64, multiplier float64) []float64 {
	switch m.Kind {
	case "generation":
		e, i := y[0], y[1]
		return []float64{-m.Sigma * e, m.Sigma*e - m.Gamma*i, m.Gamma * i}
	case "sir":
		s, i := y[0], y[1]
		f := m.Beta * multiplier * s * i / m.N
		return []float64{-f, f - m.Gamma*i, m.Gamma * i, f}
	case "age":
		out := make([]float64, len(y))
		for g, group := range m.Groups {
			pressure := 0.0
			for h, other := range m.Groups {
				pressure += m.W[g][h] * y[6*h+2] / float64(other.Population)
			}
			lambda := m.Beta * multiplier * pressure
			offset := 6 * g
			s, e, i := y[offset], y[offset+1], y[offset+2]
			f := lambda * s
			out[offset], out[offset+1], out[offset+2], out[offset+3], out[offset+4], out[offset+5] = -f, f-m.Sigma*e,
				m.Sigma*e-m.Gamma*i, (1-group.Fatality)*m.Gamma*i, group.Fatality*m.Gamma*i, m.Sigma*e
		}
		return out
	default:
		s, e, i := y[0], y[1], y[2]
		f := m.Beta * multiplier * s * i / m.N
		return []float64{-f, f - m.Sigma*e, m.Sigma*e - m.Gamma*i, (1 - m.Fatality) * m.Gamma * i, m.Fatality * m.Gamma * i, m.Sigma * e}
	}
}
func (m Model) inflowIndices() []int {
	switch m.Kind {
	case "generation":
		return []int{2}
	case "sir":
		return []int{3}
	case "age":
		a := []int{}
		for g := range m.Groups {
			a = append(a, 6*g+5)
		}
		return a
	default:
		return []int{5}
	}
}
func initial(data Data, kind string) []float64 {
	p := data.Params
	n := float64(data.Population)
	switch kind {
	case "generation":
		return []float64{1, 0, 0}
	case "sir":
		return []float64{n - p.E0 - p.I0, p.E0 + p.I0, 0, 0}
	case "age":
		out := []float64{}
		for _, g := range data.Groups {
			ng := float64(g.Population)
			e, i := p.E0*ng/n, p.I0*ng/n
			out = append(out, ng-e-i, e, i, 0, 0, 0)
		}
		return out
	default:
		return []float64{n - p.E0 - p.I0, p.E0, p.I0, 0, 0, 0}
	}
}
