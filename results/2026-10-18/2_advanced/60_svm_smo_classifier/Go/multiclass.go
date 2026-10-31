package main

type Multiclass struct{ Rest, Pair []*Model }

var classPairs = [][2]int{{1, 2}, {1, 3}, {2, 3}}

func trainMulticlass(data []Example, k Kernel, c float64, p Params) Multiclass {
	q := kernelMatrix(data, k)
	out := Multiclass{}
	for cl := 1; cl <= 3; cl++ {
		a := append([]Example(nil), data...)
		for i := range a {
			a[i].Label = -1
			if data[i].Label == cl {
				a[i].Label = 1
			}
		}
		out.Rest = append(out.Rest, train(a, q, k, c, p))
	}
	for _, pair := range classPairs {
		indices := []int{}
		for i, e := range data {
			if e.Label == pair[0] || e.Label == pair[1] {
				indices = append(indices, i)
			}
		}
		a, matrix := subset(data, q, indices)
		for i := range a {
			if a[i].Label == pair[0] {
				a[i].Label = 1
			} else {
				a[i].Label = -1
			}
		}
		out.Pair = append(out.Pair, train(a, matrix, k, c, p))
	}
	return out
}

type MultiPrediction struct {
	Rest, Pair [3]float64
	Votes      [3]int
	OVR, OVO   int
	Tie        bool
}

func (m Multiclass) classify(point Point) MultiPrediction {
	out := MultiPrediction{}
	scores := [3]float64{}
	best := 0
	for i, model := range m.Rest {
		out.Rest[i] = model.decision(point)
		if out.Rest[i] > out.Rest[best] {
			best = i
		}
	}
	out.OVR = best + 1
	for i, pair := range classPairs {
		h := m.Pair[i].decision(point)
		out.Pair[i] = h
		a, b := pair[0]-1, pair[1]-1
		if h > 0 {
			out.Votes[a]++
		} else {
			out.Votes[b]++
		}
		scores[a] += h
		scores[b] -= h
	}
	best = 0
	maximum := max(out.Votes[0], out.Votes[1], out.Votes[2])
	ties := 0
	for i, v := range out.Votes {
		if v == maximum {
			ties++
			if out.Votes[best] != maximum || scores[i] > scores[best] {
				best = i
			}
		}
	}
	out.OVO, out.Tie = best+1, ties > 1
	return out
}
