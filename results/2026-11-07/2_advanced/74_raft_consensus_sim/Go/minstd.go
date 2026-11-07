package main

type Generator struct {
	state int64
	draws int
}

func (g *Generator) Between(lo, hi int) int {
	g.state = g.state * 48271 % 2147483647
	g.draws++
	return lo + int(g.state%int64(hi-lo+1))
}
