package main

type FMIndex struct {
	Text, BWT   string
	Suffix      SuffixArray
	C           [6]int
	Checkpoints [][6]int
	OccInterval int
	Sample      map[int]int
}
type Interval struct{ Lo, Hi int }

func buildIndex(text string, occ, sample int) FMIndex {
	suffix := suffixArray(text)
	n := len(text)
	bwt := make([]byte,
		n)
	var counts [6]int
	for i, p := range suffix.SA {
		previous := (p + n - 1) % n
		bwt[i] = text[previous]
		counts[symbol(text[p])]++
	}
	f := FMIndex{Text: text,
		BWT: string(bwt), Suffix: suffix, OccInterval: occ, Sample: map[int]int{}}
	total := 0
	for c, count := range counts {
		f.C[c] = total
		total += count
	}
	counts = [6]int{}
	for i := 0; i <= n; i++ {
		if i%occ == 0 {
			f.Checkpoints = append(f.Checkpoints,
				counts)
		}
		if i < n {
			counts[symbol(bwt[i])]++
			if sample > 0 && suffix.SA[i]%sample == 0 {
				f.Sample[i] = suffix.SA[i]
			}
		}
	}
	return f
}
func (f FMIndex) occ(c, i int) int {
	q := i / f.OccInterval
	value := f.Checkpoints[q][c]
	for j := q * f.OccInterval; j < i; j++ {
		if symbol(f.BWT[j]) == c {
			value++
		}
	}
	return value
}
func (f FMIndex) lf(row int) int { c := symbol(f.BWT[row]); return f.C[c] + f.occ(c, row) }
func (f FMIndex) extend(iv Interval, base byte) Interval {
	if base == 'N' {
		return Interval{}
	}
	c := symbol(base)
	return Interval{f.C[c] + f.occ(c,
		iv.Lo), f.C[c] + f.occ(c, iv.Hi)}
}
func (f FMIndex) locate(row int) (int, int) {
	steps := 0
	for {
		if p, ok := f.Sample[row]; ok {
			return p + steps, steps
		}
		row = f.lf(row)
		steps++
	}
}
func (f FMIndex) inverse() string {
	n := len(f.Text)
	b := make([]byte, n)
	b[n-1] = '$'
	row := 0
	for p := n - 2; p >= 0; p-- {
		b[p] = f.BWT[row]
		row = f.lf(row)
	}
	return string(b)
}
func (f FMIndex) exact(q string) Interval {
	iv := Interval{0, len(f.Text)}
	for i := len(q) - 1; i >= 0; i-- {
		iv = f.extend(iv,
			q[i])
		if iv.Lo >= iv.Hi {
			return Interval{}
		}
	}
	return iv
}
