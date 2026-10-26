package main

func strongComponents(adjacency [][]int) [][]int {
	count := len(adjacency)
	order, low := make([]int, count), make([]int, count)
	onStack := make([]bool, count)
	for i := range order {
		order[i] = -1
	}
	stack := []int{}
	components := [][]int{}
	counter := 0
	type frame struct{ node, position int }
	for root := range adjacency {
		if order[root] >= 0 {
			continue
		}
		order[root], low[root] = counter, counter
		counter++
		stack = append(stack, root)
		onStack[root] = true
		work := []frame{{root, 0}}
		for len(work) > 0 {
			top := len(work) - 1
			node, position := work[top].node, work[top].position
			if position < len(adjacency[node]) {
				work[top].position++
				child := adjacency[node][position]
				if order[child] < 0 {
					order[child], low[child] = counter, counter
					counter++
					stack = append(stack, child)
					onStack[child] = true
					work = append(work, frame{child, 0})
				} else if onStack[child] {
					low[node] = min(low[node], order[child])
				}
				continue
			}
			work = work[:top]
			if len(work) > 0 {
				parent := work[len(work)-1].node
				low[parent] = min(low[parent], low[node])
			}
			if low[node] == order[node] {
				component := []int{}
				for {
					member := stack[len(stack)-1]
					stack = stack[:len(stack)-1]
					onStack[member] = false
					component = append(component, member)
					if member == node {
						break
					}
				}
				components = append(components, component)
			}
		}
	}
	return components
}
func reachable(adjacency [][]int, starts []int) []bool {
	seen := make([]bool, len(adjacency))
	stack := []int{}
	for _, start := range starts {
		if !seen[start] {
			seen[start] = true
			stack = append(stack, start)
		}
	}
	for len(stack) > 0 {
		node := stack[len(stack)-1]
		stack = stack[:len(stack)-1]
		for _, next := range adjacency[node] {
			if !seen[next] {
				seen[next] = true
				stack = append(stack, next)
			}
		}
	}
	return seen
}
func bfsDistances(adjacency [][]int, sources []int) []int {
	distance := make([]int, len(adjacency))
	for i := range distance {
		distance[i] = -1
	}
	queue := []int{}
	for _, source := range sources {
		if distance[source] < 0 {
			distance[source] = 0
			queue = append(queue, source)
		}
	}
	for head := 0; head < len(queue); head++ {
		node := queue[head]
		for _, next := range adjacency[node] {
			if distance[next] < 0 {
				distance[next] = distance[node] + 1
				queue = append(queue, next)
			}
		}
	}
	return distance
}
func weakComponents(neighbors [][]int) []int {
	labels := make([]int, len(neighbors))
	for i := range labels {
		labels[i] = -1
	}
	count := 0
	for start := range neighbors {
		if labels[start] >= 0 {
			continue
		}
		labels[start] = count
		stack := []int{start}
		for len(stack) > 0 {
			node := stack[len(stack)-1]
			stack = stack[:len(stack)-1]
			for _, next := range neighbors[node] {
				if labels[next] < 0 {
					labels[next] = count
					stack = append(stack, next)
				}
			}
		}
		count++
	}
	return labels
}
