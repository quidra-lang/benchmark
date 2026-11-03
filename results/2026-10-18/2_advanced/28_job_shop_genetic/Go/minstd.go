package main

type Minstd struct{ State int64 }

func (r *Minstd) Draw() int64          { r.State = 48271 * r.State % 2147483647; return r.State }
func (r *Minstd) Below(limit int) int  { return int(r.Draw() % int64(limit)) }
func (r *Minstd) Chance(p [2]int) bool { return r.Draw()%int64(p[1]) < int64(p[0]) }
func (r *Minstd) Shuffle(items []int) {
	for size := len(items); size > 1; size-- {
		j := r.Below(size)
		items[size-1], items[j] = items[j], items[size-1]
	}
}
