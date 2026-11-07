package main

import (
	"math"
	"sort"
)

type Similarity struct {
	Value   float64
	Common  int
	Defined bool
}
type Neighbor struct {
	Index      int
	Similarity float64
}

func largestNeighbors(candidates []Neighbor, size int) []Neighbor {
	sort.Slice(candidates, func(i, j int) bool {
		if candidates[i].Similarity != candidates[j].Similarity {
			return candidates[i].Similarity > candidates[j].Similarity
		}
		return candidates[i].Index < candidates[j].Index
	})
	return candidates[:min(size, len(candidates))]
}

type Neighborhood struct {
	Users, Items        [][]Similarity
	Counts, Differences [][]int
	Shrinkage           int
}

func newNeighborhood(d *Ratings, shrinkage int) Neighborhood {
	uCount, iCount := len(d.Users), len(d.Items)
	n := Neighborhood{Users: make([][]Similarity, uCount), Items: make([][]Similarity, iCount), Counts: make([][]int,
		iCount), Differences: make([][]int, iCount), Shrinkage: shrinkage}
	for u := range n.Users {
		n.Users[u] = make([]Similarity, uCount)
	}
	for i := range n.Items {
		n.Items[i] = make([]Similarity, iCount)
		n.Counts[i] = make([]int, iCount)
		n.Differences[i] = make([]int, iCount)
	}
	for u := 0; u < uCount; u++ {
		for v := u + 1; v < uCount; v++ {
			count, sx, sy, sxx, syy, sxy := int64(0), int64(0), int64(0), int64(0), int64(0), int64(0)
			for _, r := range d.ByUser[u] {
				if y0 := d.Values[v][r.Other]; y0 != 0 {
					x, y := int64(r.Value), int64(y0)
					count++
					sx += x
					sy += y
					sxx += x * x
					syy += y * y
					sxy += x * y
				}
			}
			if count < 2 {
				continue
			}
			num := count*sxy - sx*sy
			dx, dy := count*sxx-sx*sx, count*syy-sy*sy
			if dx == 0 || dy == 0 {
				continue
			}
			a := (num * count) * (num * count)
			b := dx * dy * (count + int64(shrinkage)) * (count + int64(shrinkage))
			sign := 0.0
			if num > 0 {
				sign = 1
			} else if num < 0 {
				sign = -1
			}
			s := Similarity{sign * math.Sqrt(float64(a)/float64(b)), int(count), true}
			n.Users[u][v] = s
			n.Users[v][u] = s
		}
	}
	for i := 0; i < iCount; i++ {
		for j := i + 1; j < iCount; j++ {
			common := []int{}
			difference := 0
			for _, r := range d.ByItem[i] {
				u := r.Other
				if y := d.Values[u][j]; y != 0 {
					common = append(common, u)
					difference += r.Value - y
				}
			}
			count := len(common)
			if count == 0 {
				continue
			}
			n.Counts[i][j] = count
			n.Counts[j][i] = count
			n.Differences[i][j] = difference
			n.Differences[j][i] = -difference
			if count < 2 {
				continue
			}
			num, left, right := 0.0, 0.0, 0.0
			for _, u := range common {
				x := float64(d.Values[u][i]) - d.UserMeans[u]
				y := float64(d.Values[u][j]) - d.UserMeans[u]
				num += x * y
				left += x * x
				right += y * y
			}
			if left == 0 || right == 0 {
				continue
			}
			value := num / math.Sqrt(left*right) * float64(count) / float64(count+shrinkage)
			s := Similarity{value, count, true}
			n.Items[i][j] = s
			n.Items[j][i] = s
		}
	}
	return n
}
func (n Neighborhood) deviation(target, source int) float64 {
	return float64(n.Differences[target][source]) / float64(n.Counts[target][source]+n.Shrinkage)
}
