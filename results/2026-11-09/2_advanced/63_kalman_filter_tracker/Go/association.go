package main

import "math"

func hungarian(cost Matrix) []int {
	n, m := len(cost), len(cost[0])
	u, v := make([]float64, n+1), make([]float64, m+1)
	p, way := make([]int, m+1), make([]int, m+1)
	for i := 1; i <= n; i++ {
		p[0] = i
		j0 := 0
		minv := make([]float64, m+1)
		used := make([]bool, m+1)
		for j := 1; j <= m; j++ {
			minv[j] = math.Inf(1)
		}
		for {
			used[j0] = true
			i0 := p[j0]
			delta := math.Inf(1)
			j1 := 0
			for j := 1; j <= m; j++ {
				if used[j] {
					continue
				}
				current := cost[i0-1][j-1] - u[i0] - v[j]
				if current < minv[j] {
					minv[j], way[j] = current, j0
				}
				if minv[j] < delta {
					delta, j1 = minv[j], j
				}
			}
			for j := 0; j <= m; j++ {
				if used[j] {
					u[p[j]] += delta
					v[j] -= delta
				} else if j > 0 {
					minv[j] -= delta
				}
			}
			j0 = j1
			if p[j0] == 0 {
				break
			}
		}
		for {
			j1 := way[j0]
			p[j0] = p[j1]
			j0 = j1
			if j0 == 0 {
				break
			}
		}
	}
	out := make([]int, n)
	for i := range out {
		out[i] = -1
	}
	for j := 1; j <= m; j++ {
		if p[j] > 0 {
			out[p[j]-1] = j - 1
		}
	}
	return out
}
func assignment(cost Matrix, usable [][]bool, columns int) []int {
	rows := len(cost)
	out := make([]int, rows)
	for i := range out {
		out[i] = -1
	}
	if rows == 0 || columns == 0 {
		return out
	}
	penalty := 1.0
	for i, row := range cost {
		for j, v := range row {
			if usable[i][j] {
				penalty += math.Abs(v)
			}
		}
	}
	matrix := zeros(rows, columns)
	for i := range matrix {
		for j := range matrix[i] {
			matrix[i][j] = penalty
			if usable[i][j] {
				matrix[i][j] = cost[i][j]
			}
		}
	}
	if rows <= columns {
		chosen := hungarian(matrix)
		for i, j := range chosen {
			if j >= 0 && usable[i][j] {
				out[i] = j
			}
		}
	} else {
		chosen := hungarian(transpose(matrix))
		for j, i := range chosen {
			if i >= 0 && usable[i][j] {
				out[i] = j
			}
		}
	}
	return out
}
