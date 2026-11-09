package main

func dbscan(neighborhoods [][]int, minPts int) ([]int, []bool) {
	labels, core := make([]int, len(neighborhoods)), make([]bool, len(neighborhoods))
	for i, n := range neighborhoods {
		labels[i] = -2
		core[i] = len(n) >= minPts
	}
	cluster := 0
	for p := range labels {
		if labels[p] != -2 {
			continue
		}
		if !core[p] {
			labels[p] = -1
			continue
		}
		labels[p] = cluster
		queue := append([]int(nil), neighborhoods[p]...)
		for head := 0; head < len(queue); head++ {
			q := queue[head]
			if labels[q] == -1 {
				labels[q] = cluster
			} else if labels[q] == -2 {
				labels[q] = cluster
				if core[q] {
					queue = append(queue, neighborhoods[q]...)
				}
			}
		}
		cluster++
	}
	return labels, core
}
