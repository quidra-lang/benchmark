package main

import "strings"

type Material struct {
	Code       byte
	Name       string
	K, Rho, CP float64
	Cells      []int
}

func readMaterials(mesh Mesh) ([]Material, []int) {
	out := []Material{}
	index := map[byte]int{}
	for _, line := range readLines("input/materials.txt") {
		a := strings.Fields(line)
		index[a[0][0]] = len(out)
		out = append(out, Material{Code: a[0][0], Name: a[1], K: number(a[2]), Rho: number(a[3]), CP: number(a[4])})
	}
	cells := make([]int, len(mesh.Codes))
	for p, code := range mesh.Codes {
		i := index[code]
		cells[p] = i
		out[i].Cells = append(out[i].Cells, p)
	}
	return out, cells
}
func capacity(m Material, mesh Mesh) float64 {
	return m.Rho * m.CP * mesh.DX * mesh.DX * mesh.Thickness
}
func interiorConductance(k1, k2, d float64) float64 { return 2 * k1 * k2 / (k1 + k2) * d }
func fixedConductance(k, d float64) float64         { return 2 * k * d }
func convectiveConductance(k, h float64, mesh Mesh) float64 {
	return 1 / (1/(h*mesh.DX*mesh.Thickness) + 1/(2*k*mesh.Thickness))
}
