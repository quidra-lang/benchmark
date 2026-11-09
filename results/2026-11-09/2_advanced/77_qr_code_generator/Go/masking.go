package main

func maskCondition(mask, x, y int) bool {
	switch mask {
	case 0:
		return (x+y)%2 == 0
	case 1:
		return y%2 == 0
	case 2:
		return x%3 == 0
	case 3:
		return (x+y)%3 == 0
	case 4:
		return (y/2+x/3)%2 == 0
	case 5:
		return x*y%2+x*y%3 == 0
	case 6:
		return (x*y%2+x*y%3)%2 == 0
	default:
		return ((x+y)%2+x*y%3)%2 == 0
	}
}
func applyMask(a, areas [][]int, mask int) [][]int {
	out := cloneGrid(a)
	for y, row := range out {
		for x := range row {
			if areas[y][x] == 0 && maskCondition(mask,
				x, y) {
				out[y][x] ^= 1
			}
		}
	}
	return out
}

type Penalty struct{ n1, n2, n3, n4 int }

func (p Penalty) total() int { return p.n1 + p.n2 + p.n3 + p.n4 }
func penalty(a [][]int) Penalty {
	n := len(a)
	p := Penalty{}
	dark := 0
	for _, row := range a {
		for _, v := range row {
			dark += v
		}
	}
	for direction := 0; direction < 2; direction++ {
		for k := 0; k < n; k++ {
			values := make([]int,
				n)
			for i := 0; i < n; i++ {
				values[i] = a[k][i]
				if direction == 1 {
					values[i] = a[i][k]
				}
			}
			for start := 0; start < n; {
				end := start + 1
				for end < n && values[end] == values[start] {
					end++
				}
				if end-start >= 5 {
					p.n1 += end - start - 2
				}
				start = end
			}
			for start := 0; start+11 <= n; start++ {
				value := 0
				for _, bit := range values[start : start+11] {
					value = value*2 + bit
				}
				if value == 0x5d0 || value == 0x05d {
					p.n3 += 40
				}
			}
		}
	}
	for y := 0; y < n-1; y++ {
		for x := 0; x < n-1; x++ {
			v := a[y][x]
			if a[y][x+1] == v && a[y+1][x] == v && a[y+1][x+1] == v {
				p.n2 += 3
			}
		}
	}
	p.n4 = 10 * (abs(20*dark-10*n*n) / (n * n))
	return p
}
