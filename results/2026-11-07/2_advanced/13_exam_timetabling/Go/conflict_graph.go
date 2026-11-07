package main

import "sort"

type Edge struct {
	first, second string
	shared        int
}
type ConflictGraph struct {
	vertices []string
	shared   map[string]map[string]int
}

func newConflictGraph(vertices []string, studentCourses map[string][]string) *ConflictGraph {
	graph := &ConflictGraph{append([]string(nil), vertices...), map[string]map[string]int{}}
	sort.Strings(graph.vertices)
	for _, id := range graph.vertices {
		graph.shared[id] = map[string]int{}
	}
	for _, ids := range studentCourses {
		for i, first := range ids {
			for _, second := range ids[i+1:] {
				graph.shared[first][second]++
				graph.shared[second][first]++
			}
		}
	}
	return graph
}
func (g *ConflictGraph) neighbours(id string) map[string]int { return g.shared[id] }
func (g *ConflictGraph) degree(id string) int                { return len(g.shared[id]) }
func (g *ConflictGraph) sharedTotal(id string) int {
	total := 0
	for _, shared := range g.shared[id] {
		total += shared
	}
	return total
}
func (g *ConflictGraph) edges() []Edge {
	edges := []Edge{}
	for _, first := range g.vertices {
		for _, second := range stringKeys(g.shared[first]) {
			if first < second {
				edges = append(edges, Edge{first, second, g.shared[first][second]})
			}
		}
	}
	return edges
}
func (g *ConflictGraph) components() [][]string {
	seen := map[string]bool{}
	components := [][]string{}
	for _, vertex := range g.vertices {
		if seen[vertex] {
			continue
		}
		seen[vertex] = true
		component := []string{vertex}
		for index := 0; index < len(component); index++ {
			for neighbour := range g.shared[component[index]] {
				if !seen[neighbour] {
					seen[neighbour] = true
					component = append(component, neighbour)
				}
			}
		}
		sort.Strings(component)
		components = append(components, component)
	}
	sort.Slice(components, func(i, j int) bool {
		if len(components[i]) != len(components[j]) {
			return len(components[i]) > len(components[j])
		}
		return components[i][0] < components[j][0]
	})
	return components
}
func (g *ConflictGraph) greedyClique(candidates []string) []string {
	candidates = append([]string(nil), candidates...)
	clique := []string{}
	for len(candidates) > 0 {
		chosen := candidates[0]
		for _, id := range candidates[1:] {
			if g.degree(id) > g.degree(chosen) || g.degree(id) == g.degree(chosen) && id < chosen {
				chosen = id
			}
		}
		clique = append(clique, chosen)
		next := []string{}
		for _, id := range candidates {
			if _, adjacent := g.shared[chosen][id]; adjacent {
				next = append(next, id)
			}
		}
		candidates = next
	}
	return clique
}
func (g *ConflictGraph) kempeChain(assignment map[string]int, start string, first, second int) []string {
	chain := []string{start}
	seen := map[string]bool{start: true}
	for index := 0; index < len(chain); index++ {
		for neighbour := range g.shared[chain[index]] {
			slot, assigned := assignment[neighbour]
			if !seen[neighbour] && assigned && (slot == first || slot == second) {
				seen[neighbour] = true
				chain = append(chain, neighbour)
			}
		}
	}
	sort.Strings(chain)
	return chain
}
func reachable(arrows map[string][]string, source, target string) bool {
	stack := []string{source}
	seen := map[string]bool{source: true}
	for len(stack) > 0 {
		node := stack[len(stack)-1]
		stack = stack[:len(stack)-1]
		if node == target {
			return true
		}
		for _, next := range arrows[node] {
			if !seen[next] {
				seen[next] = true
				stack = append(stack, next)
			}
		}
	}
	return false
}
