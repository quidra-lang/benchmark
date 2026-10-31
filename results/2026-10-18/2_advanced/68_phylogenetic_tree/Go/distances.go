package main

import "math"

type PairCounts struct{ N, S, V int }

func tally(a, b string, weights []int) PairCounts {
	var c PairCounts
	for i := range weights {
		x, y := a[i],
			b[i]
		if !isBase(x) || !isBase(y) {
			continue
		}
		w := weights[i]
		c.N += w
		if x != y {
			if x == 'A' && y == 'G' || x == 'G' && y == 'A' || x == 'C' && y == 'T' || x == 'T' && y == 'C' {
				c.S += w
			} else {
				c.V += w
			}
		}
	}
	return c
}
func distance(c PairCounts, model string, saturation float64) (float64, bool) {
	n, s, v := c.N, c.S, c.V
	if n == 0 || model == "JC" && 4*(s+v) >= 3*n || model == "K2P" && (2*s+v >= n || 2*v >= n) {
		return saturation,
			true
	}
	nf, sf, vf := float64(n), float64(s), float64(v)
	switch model {
	case "P":
		return (sf + vf) / nf, false
	case "JC":
		return -0.75 * math.Log(1-4*(sf+vf)/(3*nf)),
			false
	default:
		return -0.5*math.Log(1-2*sf/nf-vf/nf) - 0.25*math.Log(1-2*vf/nf), false
	}
}
func distanceMatrix(taxa []Record, weights []int, model string, saturation float64) [][]float64 {
	n := len(taxa)
	d := make([][]float64,
		n)
	for i := range d {
		d[i] = make([]float64, n)
	}
	for i := 0; i < n; i++ {
		for j := i + 1; j < n; j++ {
			d[i][j], _ = distance(tally(taxa[i].Sequence,
				taxa[j].Sequence, weights), model, saturation)
			d[j][i] = d[i][j]
		}
	}
	return d
}
