package main

func dispatch(in *Instance, rule string, genePositions []int) ([]int, int, int) {
	starts := make([]int, len(in.Operations))
	next, ready := map[int]int{}, map[int]int{}
	free := make([]int, in.MachineCount)
	decisions, ties := 0, 0
	for step := 0; step < len(starts); step++ {
		candidates := []int{}
		earliest := map[int]int{}
		cutoff, machine := 1<<30, 1<<30
		for _, j := range in.Jobs {
			if next[j.Number] < len(j.Operations) {
				id := j.Operations[next[j.Number]]
				o := in.Operations[id]
				es := max(ready[j.Number], free[o.Machine-1])
				ec := es + o.Duration
				candidates = append(candidates, id)
				earliest[id] = es
				if ec < cutoff || ec == cutoff && o.Machine < machine {
					cutoff, machine = ec, o.Machine
				}
			}
		}
		best, bestPriority, count, tied := -1, 1<<30, 0, 0
		for _, id := range candidates {
			o := in.Operations[id]
			if o.Machine != machine || earliest[id] >= cutoff {
				continue
			}
			count++
			priority := 0
			switch rule {
			case "SPT":
				priority = o.Duration
			case "LPT":
				priority = -o.Duration
			case "MWKR":
				priority = -o.Duration - o.Tail
			case "FIFO":
				priority = ready[o.Job]
			default:
				priority = genePositions[id]
			}
			if priority < bestPriority {
				best, bestPriority, tied = id, priority, 1
			} else if priority == bestPriority {
				tied++
			}
		}
		if count > 1 {
			decisions++
		}
		if tied > 1 {
			ties++
		}
		o := in.Operations[best]
		starts[best] = earliest[best]
		end := earliest[best] + o.Duration
		ready[o.Job], free[machine-1] = end, end
		next[o.Job]++
	}
	return starts, decisions, ties
}
