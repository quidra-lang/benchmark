package main

type Point struct{ x, y int }
type Matrix struct {
	values, areas [][]int
	order         []Point
}

func intGrid(n int) [][]int {
	a := make([][]int, n)
	for i := range a {
		a[i] = make([]int, n)
	}
	return a
}
func cloneGrid(a [][]int) [][]int {
	out := make([][]int, len(a))
	for i, row := range a {
		out[i] = append([]int(nil), row...)
	}
	return out
}
func abs(a int) int {
	if a < 0 {
		return -a
	}
	return a
}
func formatPositions(n int) ([]Point, []Point) {
	first, second := make([]Point, 15), make([]Point, 15)
	for i := 0; i <= 5; i++ {
		first[i] = Point{8,
			i}
	}
	first[6] = Point{8, 7}
	first[7] = Point{8, 8}
	first[8] = Point{7, 8}
	for i := 9; i < 15; i++ {
		first[i] = Point{14 - i,
			8}
	}
	for i := 0; i < 8; i++ {
		second[i] = Point{n - 1 - i, 8}
	}
	for i := 8; i < 15; i++ {
		second[i] = Point{8, n - 15 + i}
	}
	return first,
		second
}
func versionPositions(n int) ([]Point, []Point) {
	first, second := make([]Point, 18), make([]Point, 18)
	for i := 0; i < 18; i++ {
		first[i] = Point{n - 11 + i%3,
			i / 3}
		second[i] = Point{i / 3, n - 11 + i%3}
	}
	return first, second
}
func remainder(a, g int) int {
	degree := func(v int) int {
		d := -1
		for v > 0 {
			d++
			v >>= 1
		}
		return d
	}
	for degree(a) >= degree(g) {
		a ^= g << uint(degree(a)-degree(g))
	}
	return a
}
func formatInformation(level string, mask int) int {
	indicator := map[string]int{"L": 1, "M": 0, "Q": 3, "H": 2}[level]
	q := (8*indicator + mask) << 10
	return (q + remainder(q,
		0x537)) ^ 0x5412
}
func versionInformation(v int) int { a := v << 12; return a + remainder(a, 0x1f25) }
func writeInformation(a [][]int, positions []Point, value int) {
	for i, p := range positions {
		a[p.y][p.x] = value >> i & 1
	}
}
func readInformation(a [][]int, positions []Point) int {
	value := 0
	for i, p := range positions {
		value += a[p.y][p.x] << i
	}
	return value
}
func makeMatrix(v int, alignment []int) *Matrix {
	n := 17 + 4*v
	m := &Matrix{values: intGrid(n), areas: intGrid(n)}
	set := func(x,
		y, value, area int) {
		m.values[y][x] = value
		m.areas[y][x] = area
	}
	for _, c := range []Point{{3, 3}, {n - 4,
		3}, {3, n - 4}} {
		for dy := -4; dy <= 4; dy++ {
			for dx := -4; dx <= 4; dx++ {
				x, y := c.x+dx, c.y+dy
				if x < 0 || y < 0 || x >= n || y >= n {
					continue
				}
				d := max(abs(dx),
					abs(dy))
				value := 0
				if d == 0 || d == 1 || d == 3 {
					value = 1
				}
				set(x, y, value, 1)
			}
		}
	}
	for i := 8; i <= n-9; i++ {
		value := 1 - i%2
		set(6,
			i, value, 1)
		set(i, 6, value, 1)
	}
	for iy, cy := range alignment {
		for ix, cx := range alignment {
			if ix == 0 && iy == 0 || ix == 0 && iy == len(alignment)-1 || ix == len(alignment)-1 && iy == 0 {
				continue
			}
			for dy := -2; dy <= 2; dy++ {
				for dx := -2; dx <= 2; dx++ {
					value := 0
					if max(abs(dx),
						abs(dy)) != 1 {
						value = 1
					}
					set(cx+dx, cy+dy, value, 1)
				}
			}
		}
	}
	set(8, n-8, 1, 1)
	f1, f2 := formatPositions(n)
	for _, points := range [][]Point{f1, f2} {
		for _, p := range points {
			set(p.x, p.y, 0, 2)
		}
	}
	if v >= 7 {
		g1, g2 := versionPositions(n)
		for _, points := range [][]Point{g1, g2} {
			for _, p := range points {
				set(p.x, p.y, 0, 3)
			}
			writeInformation(m.values,
				points, versionInformation(v))
		}
	}
	pair := 0
	for r := n - 1; r >= 1; r -= 2 {
		if r == 6 {
			r--
		}
		for step := 0; step < n; step++ {
			y := step
			if pair%2 == 0 {
				y = n - 1 - step
			}
			for x := r; x >= r-1; x-- {
				if m.areas[y][x] == 0 {
					m.order = append(m.order,
						Point{x, y})
				}
			}
		}
		pair++
	}
	return m
}
func rotate(a [][]int) [][]int {
	n := len(a)
	out := intGrid(n)
	for y := 0; y < n; y++ {
		for x := 0; x < n; x++ {
			out[y][x] = a[n-1-x][y]
		}
	}
	return out
}
func transpose(a [][]int) [][]int {
	n := len(a)
	out := intGrid(n)
	for y := 0; y < n; y++ {
		for x := 0; x < n; x++ {
			out[y][x] = a[x][y]
		}
	}
	return out
}
