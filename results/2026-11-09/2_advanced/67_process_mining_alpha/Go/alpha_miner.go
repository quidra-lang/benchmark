package main

type Masks struct{ A, B int }

func triangles(log []Trace) map[Pair]int {
	t := map[Pair]int{}
	for _, v := range log {
		a := v.Activities
		for i := 0; i+2 < len(a); i++ {
			if a[i] == a[i+2] && a[i] != a[i+1] {
				t[Pair{a[i],
					a[i+1]}] += v.Weight
			}
		}
	}
	return t
}
func alphaRelation(d, tri map[Pair]int, a, b string) string {
	ab, ba := d[Pair{a, b}] > 0, d[Pair{b, a}] > 0
	loop := a != b && tri[Pair{a,
		b}] > 0 && tri[Pair{b, a}] > 0
	if ab && (!ba || loop) {
		return "->"
	}
	if ba && (!ab || loop) {
		return "<-"
	}
	if ab && ba {
		return "||"
	}
	return "#"
}
func candidate(m Masks, names []string, rel func(string, string) string) bool {
	if m.A == 0 || m.B == 0 {
		return false
	}
	for i, a := range names {
		if m.A>>i&1 != 0 {
			for j, b := range names {
				if m.A>>j&1 != 0 && rel(a, b) != "#" {
					return false
				}
				if m.B>>j&1 != 0 && rel(a,
					b) != "->" {
					return false
				}
			}
		}
		if m.B>>i&1 != 0 {
			for j, b := range names {
				if m.B>>j&1 != 0 && rel(a, b) != "#" {
					return false
				}
			}
		}
	}
	return true
}
func maskMembers(mask int, names []string) []string {
	var a []string
	for i, name := range names {
		if mask>>i&1 != 0 {
			a = append(a, name)
		}
	}
	return a
}
func compareSequence(a, b []string) int {
	for i := 0; i < len(a) && i < len(b); i++ {
		if a[i] < b[i] {
			return -1
		}
		if a[i] > b[i] {
			return 1
		}
	}
	if len(a) < len(b) {
		return -1
	}
	if len(a) > len(b) {
		return 1
	}
	return 0
}
func compareMasks(a, b Masks, names []string) int {
	if n := compareSequence(maskMembers(a.A, names), maskMembers(b.A,
		names)); n != 0 {
		return n
	}
	return compareSequence(maskMembers(a.B, names), maskMembers(b.B, names))
}
