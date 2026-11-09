package main

import "sort"

type GoldenRecord struct{ A, B, C, D, FC, FD float64 }
type GoldenResult struct {
	X, Value float64
	Records  []GoldenRecord
}

func golden(f func(float64) float64, a, b float64, n int) GoldenResult {
	const phi = .6180339887498949
	c, d := b-phi*(b-a), a+phi*(b-a)
	fc, fd := f(c), f(d)
	out := GoldenResult{}
	out.Records = append(out.Records, GoldenRecord{a, b, c, d, fc, fd})
	for i := 0; i < n; i++ {
		if fc < fd {
			b, d, fd = d, c, fc
			c = b - phi*(b-a)
			fc = f(c)
		} else {
			a, c, fc = c, d, fd
			d = a + phi*(b-a)
			fd = f(d)
		}
		out.Records = append(out.Records, GoldenRecord{a, b, c, d, fc, fd})
	}
	out.X, out.Value = d, fd
	if fc < fd {
		out.X, out.Value = c, fc
	}
	return out
}

type Vertex struct {
	Beta, Gamma, Value float64
	Number             int
}
type NelderRecord struct {
	Operation string
	Best      Vertex
}
type NelderResult struct {
	Initial, Final []Vertex
	Records        []NelderRecord
}

func vertexLess(a, b Vertex) bool {
	if a.Value != b.Value {
		return a.Value < b.Value
	}
	return a.Number < b.Number
}
func nelder(f func(float64, float64) float64, beta, gamma float64, p Params) NelderResult {
	serial := 0
	create := func(b, g float64) Vertex { v := Vertex{b, g, f(b, g), serial}; serial++; return v }
	vertices := []Vertex{create(beta, gamma), create(beta+p.DeltaBeta, gamma), create(beta, gamma+p.DeltaGamma)}
	out := NelderResult{Initial: append([]Vertex(nil), vertices...)}
	sortVertices := func() { sort.Slice(vertices, func(i, j int) bool { return vertexLess(vertices[i], vertices[j]) }) }
	for iteration := 0; iteration < p.Nelder; iteration++ {
		sortVertices()
		x1, x2, x3 := vertices[0], vertices[1], vertices[2]
		ob, og := (x1.Beta+x2.Beta)/2, (x1.Gamma+x2.Gamma)/2
		rb, rg := ob+p.Alpha*(ob-x3.Beta), og+p.Alpha*(og-x3.Gamma)
		fr := f(rb, rg)
		operation := "reflect"
		ab, ag, av := rb, rg, fr
		shrink := false
		if fr < x1.Value {
			eb, eg := ob+p.Chi*(rb-ob), og+p.Chi*(rg-og)
			fe := f(eb, eg)
			if fe < fr {
				operation, ab, ag, av = "expand", eb, eg, fe
			}
		} else if fr < x2.Value {
		} else if fr < x3.Value {
			cb, cg := ob+p.Psi*(rb-ob), og+p.Psi*(rg-og)
			fc := f(cb, cg)
			if fc <= fr {
				operation, ab, ag, av = "contract_out", cb, cg, fc
			} else {
				shrink = true
			}
		} else {
			cb, cg := ob+p.Psi*(x3.Beta-ob), og+p.Psi*(x3.Gamma-og)
			fc := f(cb, cg)
			if fc < x3.Value {
				operation, ab, ag, av = "contract_in", cb, cg, fc
			} else {
				shrink = true
			}
		}
		if shrink {
			operation = "shrink"
			vertices[1] = create(x1.Beta+p.Omega*(x2.Beta-x1.Beta), x1.Gamma+p.Omega*(x2.Gamma-x1.Gamma))
			vertices[2] = create(x1.Beta+p.Omega*(x3.Beta-x1.Beta), x1.Gamma+p.Omega*(x3.Gamma-x1.Gamma))
		} else {
			vertices[2] = Vertex{ab, ag, av, serial}
			serial++
		}
		sortVertices()
		out.Records = append(out.Records, NelderRecord{operation, vertices[0]})
	}
	out.Final = append([]Vertex(nil), vertices...)
	return out
}
