package main

type Minstd struct { state int64 }
func (r *Minstd) Draw() int64 { r.state = 48271 * r.state % 2147483647; return r.state }
func selectWeight(weights []int, value int64) int {
 total := 0; for _, w := range weights { total += w }; q := value % int64(total)
 for i, w := range weights { if q < int64(w) { return i }; q -= int64(w) }; panic("weights")
}
