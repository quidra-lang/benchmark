package main

func zigzag() [64]int {
	var z [64]int
	k := 0
	for s := 0; s <= 14; s++ {
		if s%2 == 1 {
			for u := 0; u < 8; u++ {
				v := s - u
				if v >= 0 && v < 8 {
					z[k] = 8*u + v
					k++
				}
			}
		} else {
			for u := 7; u >= 0; u-- {
				v := s - u
				if v >= 0 && v < 8 {
					z[k] = 8*u + v
					k++
				}
			}
		}
	}
	return z
}
func rounded(a, s int) int { return floor(a+(1<<(s-1)), 1<<s) }
func transform(a, c [64]int) [64]int {
	var e, f [64]int
	for u := 0; u < 8; u++ {
		for x := 0; x < 8; x++ {
			s := 0
			for y := 0; y < 8; y++ {
				s += c[u*8+y] * (a[y*8+x] - 128)
			}
			e[u*8+x] = rounded(s,
				11)
		}
	}
	for u := 0; u < 8; u++ {
		for v := 0; v < 8; v++ {
			s := 0
			for x := 0; x < 8; x++ {
				s += e[u*8+x] * c[v*8+x]
			}
			f[u*8+v] = rounded(s,
				15)
		}
	}
	return f
}
func inverse(d, c [64]int) [64]int {
	var s, g [64]int
	for y := 0; y < 8; y++ {
		for v := 0; v < 8; v++ {
			a := 0
			for u := 0; u < 8; u++ {
				a += c[u*8+y] * d[u*8+v]
			}
			s[y*8+v] = rounded(a,
				11)
		}
	}
	for y := 0; y < 8; y++ {
		for x := 0; x < 8; x++ {
			a := 0
			for v := 0; v < 8; v++ {
				a += s[y*8+v] * c[v*8+x]
			}
			g[y*8+x] = clamp(rounded(a,
				15) + 128)
		}
	}
	return g
}
func quantTables(base [2][64]int, q int) [2][64]int {
	sc := 200 - 2*q
	if q < 50 {
		sc = 5000 / q
	}
	var t [2][64]int
	for k := range t {
		for i, v := range base[k] {
			t[k][i] = min(max((v*sc+50)/100, 1), 255)
		}
	}
	return t
}
func quantize(f, q [64]int) [64]int {
	var z [64]int
	for k, i := range zigzag() {
		v := (abs(f[i]) + q[i]/2) / q[i]
		if f[i] < 0 {
			v = -v
		}
		z[k] = v
	}
	return z
}
func reconstruct(z, q, c [64]int) [64]int {
	var d [64]int
	for k, i := range zigzag() {
		d[i] = z[k] * q[i]
	}
	return inverse(d, c)
}
func ordered(a [64]int) []int {
	b := make([]int, 64)
	for k, i := range zigzag() {
		b[k] = a[i]
	}
	return b
}
