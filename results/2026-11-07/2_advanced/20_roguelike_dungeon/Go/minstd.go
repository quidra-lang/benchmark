package main

type Minstd struct{ State int64 }

func (rng *Minstd) Draw() int64 {
	rng.State = (48271 * rng.State) % 2147483647
	return rng.State
}
func (rng *Minstd) Rnd(n int) int { return int(rng.Draw() % int64(n)) }
func (rng *Minstd) Roll(count, sides int) int {
	total := 0
	for range count {
		total += 1 + rng.Rnd(sides)
	}
	return total
}
func (rng *Minstd) Select(weights []int) int {
	total := 0
	for _, weight := range weights {
		total += weight
	}
	q := rng.Rnd(total)
	cumulative := 0
	for index, weight := range weights {
		cumulative += weight
		if q < cumulative {
			return index
		}
	}
	panic("empty weights")
}
