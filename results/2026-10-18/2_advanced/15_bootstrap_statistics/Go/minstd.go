package main

type Minstd struct{ state int64 }

func (g *Minstd) draw() int64         { g.state = 48271 * g.state % 2147483647; return g.state }
func (g *Minstd) below(limit int) int { return int(g.draw() % int64(limit)) }
func shuffle[T any](generator *Minstd, items []T) {
	for i := len(items) - 1; i > 0; i-- {
		j := generator.below(i + 1)
		items[i], items[j] = items[j], items[i]
	}
}
