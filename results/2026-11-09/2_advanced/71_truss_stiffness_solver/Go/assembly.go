package main

import "math"

type Loads struct {
	External, Temperature, Total, P0 []float64
	Settlement                       bool
}

func geometry(m *Model) {
	for i := range m.Members {
		member := &m.Members[i]
		a, b := m.Nodes[member.I], m.Nodes[member.J]
		dx,
			dy := b.X-a.X, b.Y-a.Y
		member.Length = math.Sqrt(float64(dx*dx + dy*dy))
		member.C = float64(dx) / member.Length
		member.S = float64(dy) / member.Length
		member.DOFs = [4]int{2 * m.Number[member.I],
			2*m.Number[member.I] + 1, 2 * m.Number[member.J], 2*m.Number[member.J] + 1}
	}
}
func matrix(rows, columns int) [][]float64 {
	a := make([][]float64, rows)
	for i := range a {
		a[i] = make([]float64, columns)
	}
	return a
}
func stiffness(m Model, sections []int, removed int) [][]float64 {
	nd := 2 * len(m.Nodes)
	global := matrix(nd,
		nd)
	for i, member := range m.Members {
		if i == removed {
			continue
		}
		material, section := m.Materials[member.Material],
			m.Sections[sections[i]]
		k := material.E * section.Area / member.Length
		c, s := member.C, member.S
		kxx, kxy,
			kyy := k*(c*c), k*(c*s), k*(s*s)
		local := [4][4]float64{{kxx, kxy, -kxx, -kxy}, {kxy, kyy, -kxy, -kyy}, {-kxx,
			-kxy, kxx, kxy}, {-kxy, -kyy, kxy, kyy}}
		for r, dofr := range member.DOFs {
			for c, dofc := range member.DOFs {
				global[dofr][dofc] += local[r][c]
			}
		}
	}
	return global
}
func memberWeight(member Member, section Section, material Material) float64 {
	return material.Rho * 9.81 * section.Area * member.Length / 1000000000
}
func loadVectors(load LoadCase, m Model, sections []int, removed int) Loads {
	nd := 2 * len(m.Nodes)
	l := Loads{External: make([]float64,
		nd), Temperature: make([]float64, nd), Total: make([]float64, nd), P0: make([]float64, len(m.Members))}
	for _, line := range load.Lines {
		switch line.Kind {
		case "FORCE":
			d := 2 * m.Number[line.Item]
			l.External[d] += line.X * 1000
			l.External[d+1] += line.Y * 1000
		case "TEMPERATURE":
			if line.Item == removed {
				continue
			}
			member := m.Members[line.Item]
			material,
				section := m.Materials[member.Material], m.Sections[sections[line.Item]]
			p0 := material.E * section.Area * material.Alpha * line.X
			l.P0[line.Item] = p0
			t := [4]float64{-member.C,
				-member.S, member.C, member.S}
			for i, d := range member.DOFs {
				l.Temperature[d] += p0 * t[i]
			}
		case "SELFWEIGHT":
			for i, member := range m.Members {
				if i == removed {
					continue
				}
				w := memberWeight(member, m.Sections[sections[i]],
					m.Materials[member.Material])
				l.External[member.DOFs[1]] -= w / 2
				l.External[member.DOFs[3]] -= w / 2
			}
		case "SETTLEMENT":
			l.Settlement = true
		}
	}
	for d := 0; d < nd; d++ {
		l.Total[d] = l.External[d] + l.Temperature[d]
	}
	return l
}
