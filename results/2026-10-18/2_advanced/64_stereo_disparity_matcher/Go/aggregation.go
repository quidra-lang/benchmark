package main

var directions = [][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {-1, -1}, {-1, 1}, {1, -1}}

func aggregate(base Volume, left Image, p Params, observe func(int, Volume)) Volume {
	n, d := len(base), p.Max-p.Min+1
	summed := make(Volume, n)
	for i := range summed {
		summed[i] = make([]int64, d)
	}
	for path := 0; path < p.Paths; path++ {
		r := directions[path]
		values := make(Volume, n)
		for i := range values {
			values[i] = make([]int64, d)
		}
		y0, yEnd, ys := 0, left.H, 1
		if r[1] < 0 {
			y0, yEnd, ys = left.H-1, -1, -1
		}
		x0, xEnd, xs := 0, left.W, 1
		if r[0] < 0 {
			x0, xEnd, xs = left.W-1, -1, -1
		}
		for y := y0; y != yEnd; y += ys {
			for x := x0; x != xEnd; x += xs {
				index := y*left.W + x
				qx, qy := x-r[0], y-r[1]
				if qx < 0 || qx >= left.W || qy < 0 || qy >= left.H {
					copy(values[index], base[index])
				} else {
					q := qy*left.W + qx
					minimum := values[q][0]
					for _, v := range values[q][1:] {
						minimum = min(minimum, v)
					}
					penalty := max(p.P1, p.P2*p.Gamma/(p.Gamma+int64(absolute(left.Pixels[index]-left.Pixels[q]))))
					for di := 0; di < d; di++ {
						best := min(values[q][di], minimum+penalty)
						if di > 0 {
							best = min(best, values[q][di-1]+p.P1)
						}
						if di+1 < d {
							best = min(best, values[q][di+1]+p.P1)
						}
						values[index][di] = base[index][di] + best - minimum
					}
				}
				for di, v := range values[index] {
					summed[index][di] += v
				}
			}
		}
		observe(path+1, summed)
	}
	return summed
}
