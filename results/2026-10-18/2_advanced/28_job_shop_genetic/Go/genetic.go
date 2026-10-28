package main

func geneOperations(in *Instance, chromosome []int) []int {
	counts := map[int]int{}
	result := []int{}
	for _, j := range chromosome {
		result = append(result, in.ByJob[j].Operations[counts[j]])
		counts[j]++
	}
	return result
}
func decode(in *Instance, chromosome []int) []int {
	starts := make([]int, len(in.Operations))
	ready := map[int]int{}
	free := make([]int, in.MachineCount)
	for _, id := range geneOperations(in, chromosome) {
		o := in.Operations[id]
		starts[id] = max(ready[o.Job], free[o.Machine-1])
		end := starts[id] + o.Duration
		ready[o.Job], free[o.Machine-1] = end, end
	}
	return starts
}
func tournament(r *Minstd, values []int, size int) int {
	best := -1
	for i := 0; i < size; i++ {
		pick := r.Below(len(values))
		if best < 0 || values[pick] < values[best] || values[pick] == values[best] && pick < best {
			best = pick
		}
	}
	return best
}
func preserveOrder(keeper, donor []int, kept map[int]bool) []int {
	fillers := []int{}
	for _, g := range donor {
		if !kept[g] {
			fillers = append(fillers, g)
		}
	}
	child := append([]int(nil), keeper...)
	pos := 0
	for i, g := range child {
		if !kept[g] {
			child[i] = fillers[pos]
			pos++
		}
	}
	return child
}
func crossover(r *Minstd, a, b []int, jobs []Job) ([]int, []int) {
	kept := map[int]bool{}
	for _, j := range jobs {
		if r.Below(2) == 0 {
			kept[j.Number] = true
		}
	}
	return preserveOrder(a, b, kept), preserveOrder(b, a, kept)
}
func swapMutation(r *Minstd, c []int) {
	a, b := r.Below(len(c)), r.Below(len(c))
	c[a], c[b] = c[b], c[a]
}
func insertMutation(r *Minstd, c []int) {
	a, b := r.Below(len(c)), r.Below(len(c))
	value := c[a]
	if a < b {
		copy(c[a:b], c[a+1:b+1])
	} else if b < a {
		copy(c[b+1:a+1], c[b:a])
	}
	c[b] = value
}
