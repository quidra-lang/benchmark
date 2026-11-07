package main

type Shanten struct{ memo map[string]int }

func newShanten() *Shanten { return &Shanten{memo: map[string]int{}} }
func (s *Shanten) standard(a [34]int, m, t, h int) int {
	var bytes [37]byte
	for i, c := range a {
		bytes[i] = byte(c)
	}
	bytes[34],
		bytes[35], bytes[36] = byte(m), byte(t), byte(h)
	key := string(bytes[:])
	if value, ok := s.memo[key]; ok {
		return value
	}
	best := 8 - 2*m - min(t,
		4-m) - h
	first := -1
	for i, c := range a {
		if c > 0 {
			first = i
			break
		}
	}
	if first < 0 {
		return best
	}
	a[first]--
	best = min(best,
		s.standard(a, m, t, h))
	a[first]++
	if m < 4 {
		if a[first] >= 3 {
			a[first] -= 3
			best = min(best, s.standard(a,
				m+1, t, h))
			a[first] += 3
		}
		if first < 27 && first%9 <= 6 && a[first+1] > 0 && a[first+2] > 0 {
			a[first]--
			a[first+1]--
			a[first+2]--
			best = min(best,
				s.standard(a, m+1, t, h))
			a[first]++
			a[first+1]++
			a[first+2]++
		}
	}
	if a[first] >= 2 {
		a[first] -= 2
		if h == 0 {
			best = min(best,
				s.standard(a, m, t, 1))
		}
		if t < 4 {
			best = min(best, s.standard(a, m, t+1, h))
		}
		a[first] += 2
	}
	if t < 4 && first < 27 {
		for delta := 1; delta <= 2; delta++ {
			if first%9+delta <= 8 && a[first+delta] > 0 {
				a[first]--
				a[first+delta]--
				best = min(best,
					s.standard(a, m, t+1, h))
				a[first]++
				a[first+delta]++
			}
		}
	}
	s.memo[key] = best
	return best
}
func (s *Shanten) numbers(a [34]int) [3]int {
	pairs, distinct, orphans := 0, 0, 0
	hasOrphanPair := false
	for kind, n := range a {
		if n > 0 {
			distinct++
			if yaochuu(kind) {
				orphans++
			}
		}
		if n >= 2 {
			pairs++
			if yaochuu(kind) {
				hasOrphanPair = true
			}
		}
	}
	kokushi := 13 - orphans
	if hasOrphanPair {
		kokushi--
	}
	return [3]int{s.standard(a,
		0, 0, 0), 6 - pairs + max(0, 7-distinct), kokushi}
}
func minimumShanten(a [3]int) int { return min(a[0], a[1], a[2]) }
