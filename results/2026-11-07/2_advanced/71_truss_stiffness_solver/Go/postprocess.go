package main

import "math"

type Result struct {
	Name                                       string
	Displacements, Forces, Reactions, External []float64
}

func axialForces(displacements, p0 []float64, m Model, sections []int, removed int) []float64 {
	forces := make([]float64,
		len(m.Members))
	for i, member := range m.Members {
		if i == removed {
			continue
		}
		a := member.DOFs
		e := (displacements[a[2]]-displacements[a[0]])*member.C + (displacements[a[3]]-displacements[a[1]])*member.S
		k := m.Materials[member.Material].E * m.Sections[sections[i]].Area / member.Length
		forces[i] = k*e - p0[i]
	}
	return forces
}
func reactions(k [][]float64, d, f []float64, restrained []int) []float64 {
	r := make([]float64, len(d))
	for _, row := range restrained {
		sum := 0.0
		for col := range d {
			sum += k[row][col] * d[col]
		}
		r[row] = sum - f[row]
	}
	return r
}
func combination(combo Combination, cases []Result) Result {
	nd, nm := len(cases[0].Displacements), len(cases[0].Forces)
	r := Result{combo.Name,
		make([]float64, nd), make([]float64, nm), make([]float64, nd), make([]float64, nd)}
	for _, term := range combo.Terms {
		c := cases[term.Case]
		for i := 0; i < nd; i++ {
			r.Displacements[i] += term.Factor * c.Displacements[i]
			r.Reactions[i] += term.Factor * c.Reactions[i]
			r.External[i] += term.Factor * c.External[i]
		}
		for i := 0; i < nm; i++ {
			r.Forces[i] += term.Factor * c.Forces[i]
		}
	}
	return r
}
func equilibrium(r Result, m Model) (float64, float64) {
	z := make([]float64, len(r.External))
	scale := 1.0
	for i := range z {
		z[i] = r.External[i] + r.Reactions[i]
		scale = math.Max(scale,
			math.Abs(r.External[i]))
		scale = math.Max(scale, math.Abs(r.Reactions[i]))
	}
	for i, member := range m.Members {
		t := [4]float64{member.C,
			member.S, -member.C, -member.S}
		for k, d := range member.DOFs {
			z[d] += r.Forces[i] * t[k]
		}
	}
	maximum := 0.0
	for _, v := range z {
		maximum = math.Max(maximum, math.Abs(v))
	}
	return maximum, scale
}
