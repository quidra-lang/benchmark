package main

func dependency(d map[Pair]int, a, b string) Ratio {
	ab, ba := d[Pair{a, b}], d[Pair{b, a}]
	return ratio(ab-ba, ab+ba+1)
}
func loopMeasure(n int) Ratio { return ratio(n, n+1) }
func splitMeasure(d map[Pair]int, a, b, c string, join bool) Ratio {
	n := d[Pair{b, c}] + d[Pair{c, b}]
	den := d[Pair{a,
		b}] + d[Pair{a, c}] + 1
	if join {
		den = d[Pair{b, a}] + d[Pair{c, a}] + 1
	}
	return ratio(n, den)
}
