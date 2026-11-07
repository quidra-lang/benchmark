package main

import (
	"fmt"
	"sort"
)

type Regions struct {
	Known, Nonocc, Occluded, Disc []bool
	Layers                        []int
	LayerCounts                   map[int]int
}
type Metrics struct {
	Pixels, Valid, Bad1, Bad2, Exact int
	Error                            int64
}

func truthRegions(gt Image) Regions {
	n := len(gt.Pixels)
	out := Regions{make([]bool, n), make([]bool, n), make([]bool, n), make([]bool, n), nil, map[int]int{}}
	for y := 0; y < gt.H; y++ {
		nearest := map[int]int{}
		for x := 0; x < gt.W; x++ {
			g := gt.Pixels[y*gt.W+x]
			if g > 0 {
				nearest[x-g] = max(nearest[x-g], g)
			}
		}
		for x := 0; x < gt.W; x++ {
			index := y*gt.W + x
			g := gt.Pixels[index]
			if g == 0 {
				continue
			}
			out.Known[index] = true
			out.LayerCounts[g]++
			if x-g < 0 || nearest[x-g] > g {
				out.Occluded[index] = true
			} else {
				out.Nonocc[index] = true
				for dy := -1; dy <= 1; dy++ {
					for dx := -1; dx <= 1; dx++ {
						xx, yy := x+dx, y+dy
						if (dx == 0 && dy == 0) || xx < 0 || xx >= gt.W || yy < 0 || yy >= gt.H {
							continue
						}
						other := gt.Pixels[yy*gt.W+xx]
						if other > 0 && absolute(other-g) >= 2 {
							out.Disc[index] = true
						}
					}
				}
			}
		}
	}
	for g := range out.LayerCounts {
		out.Layers = append(out.Layers, g)
	}
	sort.Ints(out.Layers)
	return out
}
func evaluate(disparity, truth []int, mask []bool) Metrics {
	out := Metrics{}
	for i, inside := range mask {
		if !inside {
			continue
		}
		out.Pixels++
		if disparity[i] == 0 {
			out.Bad1++
			out.Bad2++
			continue
		}
		out.Valid++
		error := absolute(disparity[i] - truth[i])
		out.Error += int64(error)
		if error == 0 {
			out.Exact++
		}
		if error > 1 {
			out.Bad1++
		}
		if error > 2 {
			out.Bad2++
		}
	}
	return out
}
func ratio(a, b int64) string {
	if b == 0 {
		return "0/1 0.00"
	}
	x, y := a, b
	for y != 0 {
		x, y = y, x%y
	}
	return fmt.Sprintf("%d/%d %s", a/x, b/x, decimal2(100*a, b))
}
