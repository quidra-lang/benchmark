package main

import (
	"fmt"
	"os"
	"slices"
	"sort"
	"strconv"
	"strings"
)

var regionNames = []string{"CORE", "IN", "OUT", "TUBE", "IN_TENDRIL", "OUT_TENDRIL", "OTHER"}
var quantityNames = []string{"in_degree", "pagerank", "cheirank", "authority", "hub", "trustrank", "harmonic"}

const (
	coreRegion = iota
	inRegion
	outRegion
	tubeRegion
	inTendril
	outTendril
	otherRegion
)

func total(values []float64) float64 {
	sum := 0.0
	for _, value := range values {
		sum += value
	}
	return sum
}
func sequence(count int) []int {
	values := make([]int, count)
	for i := range values {
		values[i] = i
	}
	return values
}
func integerText(values []int) string {
	parts := []string{}
	for _, value := range values {
		parts = append(parts, strconv.Itoa(value))
	}
	return strings.Join(parts, " ")
}
func joinBlocks(blocks [][]string) []string {
	lines := []string{}
	for i, block := range blocks {
		if i > 0 {
			lines = append(lines, "")
		}
		lines = append(lines, block...)
	}
	return lines
}
func rankOrder(values []float64) []int {
	order := sequence(len(values))
	sort.SliceStable(order, func(i, j int) bool { return scaled(values[order[i]]) > scaled(values[order[j]]) })
	return order
}
func positions(order []int) []int {
	rank := make([]int, len(order))
	for i, node := range order {
		rank[node] = i + 1
	}
	return rank
}
func topList(values []float64, limit int) []int {
	nodes := []int{}
	for _, node := range rankOrder(values) {
		if scaled(values[node]) > 0 && len(nodes) < limit {
			nodes = append(nodes, node)
		}
	}
	return nodes
}
func rankedCounts(counts []int, limit int) []int {
	nodes := []int{}
	for node, count := range counts {
		if count > 0 {
			nodes = append(nodes, node)
		}
	}
	sort.SliceStable(nodes, func(i, j int) bool { return counts[nodes[i]] > counts[nodes[j]] })
	return nodes[:min(limit, len(nodes))]
}
func distributionLines(values []int) []string {
	counts := map[int]int{}
	for _, value := range values {
		counts[value]++
	}
	keys := []int{}
	for value := range counts {
		keys = append(keys, value)
	}
	sort.Ints(keys)
	lines := []string{}
	for _, value := range keys {
		lines = append(lines, fmt.Sprintf("%d %d", value, counts[value]))
	}
	return lines
}
func runPageRank(edges [][]WeightedEdge, teleport []int, damping float64, s Settings) *PageRankResult {
	return powerIteration(edges, teleport, damping, s.iterations, s.tolerance)
}

type Link struct{ source, target int }
type Ignored struct {
	record LinkRecord
	reason string
}

func classifyLinks(records []LinkRecord, indexOf map[int]int) ([]Link, []Ignored) {
	accepted := map[Link]bool{}
	ignored := []Ignored{}
	for _, record := range records {
		source, knownSource := indexOf[record.source]
		target, knownTarget := indexOf[record.target]
		reason := ""
		link := Link{source, target}
		if !knownSource || !knownTarget {
			reason = "unknown"
		} else if source == target {
			reason = "self"
		} else if accepted[link] {
			reason = "duplicate"
		} else {
			accepted[link] = true
		}
		if reason != "" {
			ignored = append(ignored, Ignored{record, reason})
		}
	}
	links := []Link{}
	for link := range accepted {
		links = append(links, link)
	}
	return links, ignored
}

type Graph struct {
	pages                    []Page
	links                    []Link
	linkSet                  map[Link]bool
	successors, predecessors [][]int
}

func newGraph(pages []Page, links []Link) *Graph {
	ordered := append([]Link(nil), links...)
	sort.Slice(ordered, func(i, j int) bool {
		if ordered[i].source != ordered[j].source {
			return ordered[i].source < ordered[j].source
		}
		return ordered[i].target < ordered[j].target
	})
	g := &Graph{pages: pages, links: ordered, linkSet: map[Link]bool{}, successors: make([][]int, len(pages)), predecessors: make([][]int, len(pages))}
	for _, link := range ordered {
		g.linkSet[link] = true
		g.successors[link.source] = append(g.successors[link.source], link.target)
		g.predecessors[link.target] = append(g.predecessors[link.target], link.source)
	}
	return g
}
func (g *Graph) intraHost(link Link) bool {
	return g.pages[link.source].host == g.pages[link.target].host
}
func (g *Graph) interHostLinks(links []Link) []Link {
	result := []Link{}
	for _, link := range links {
		if !g.intraHost(link) {
			result = append(result, link)
		}
	}
	return result
}
func (g *Graph) dangling() []int {
	nodes := []int{}
	for node, targets := range g.successors {
		if len(targets) == 0 {
			nodes = append(nodes, node)
		}
	}
	return nodes
}
func (g *Graph) ids(nodes []int) []int {
	ids := make([]int, len(nodes))
	for i, node := range nodes {
		ids[i] = g.pages[node].id
	}
	return ids
}
func (g *Graph) forwardEdges() [][]WeightedEdge {
	edges := make([][]WeightedEdge, len(g.pages))
	for node, sources := range g.predecessors {
		for _, source := range sources {
			edges[node] = append(edges[node], WeightedEdge{source, 1})
		}
	}
	return edges
}
func (g *Graph) reverseEdges() [][]WeightedEdge {
	edges := make([][]WeightedEdge, len(g.pages))
	for node, targets := range g.successors {
		for _, target := range targets {
			edges[node] = append(edges[node], WeightedEdge{target, 1})
		}
	}
	return edges
}
func (g *Graph) describe(position, node int, values ...string) string {
	page := g.pages[node]
	parts := []string{strconv.Itoa(position), strconv.Itoa(page.id)}
	parts = append(parts, values...)
	return strings.Join(append(parts, page.host, page.title), " ")
}
func kcoreNumbers(neighbors [][]int) []int {
	remaining := make([]int, len(neighbors))
	for node, group := range neighbors {
		remaining[node] = len(group)
	}
	removed := make([]bool, len(neighbors))
	core := make([]int, len(neighbors))
	level, left := 0, len(neighbors)
	for left > 0 {
		candidate := -1
		for node := range neighbors {
			if !removed[node] && remaining[node] <= level {
				candidate = node
				break
			}
		}
		if candidate < 0 {
			level++
			continue
		}
		removed[candidate] = true
		core[candidate] = level
		left--
		for _, next := range neighbors[candidate] {
			if !removed[next] {
				remaining[next]--
			}
		}
	}
	return core
}

type Undirected struct {
	neighbors                                                                 [][]int
	edgeCount, closed, possible, eligible, degeneracy, weakCount, weakLargest int
	averageClustering                                                         float64
	kcore                                                                     []int
}

func newUndirected(g *Graph) *Undirected {
	n := len(g.pages)
	adjacent := make([][]bool, n)
	for i := range adjacent {
		adjacent[i] = make([]bool, n)
	}
	for _, link := range g.links {
		adjacent[link.source][link.target] = true
		adjacent[link.target][link.source] = true
	}
	u := &Undirected{neighbors: make([][]int, n)}
	localSum := 0.0
	for node, row := range adjacent {
		for next, exists := range row {
			if exists {
				u.neighbors[node] = append(u.neighbors[node], next)
			}
		}
		neighbors := u.neighbors[node]
		degree := len(neighbors)
		u.edgeCount += degree
		if degree < 2 {
			continue
		}
		closed := 0
		for i, first := range neighbors {
			for _, second := range neighbors[i+1:] {
				if adjacent[first][second] {
					closed++
				}
			}
		}
		possible := degree * (degree - 1) / 2
		u.closed += closed
		u.possible += possible
		u.eligible++
		localSum += float64(closed) / float64(possible)
	}
	u.edgeCount /= 2
	u.averageClustering = localSum / float64(u.eligible)
	u.kcore = kcoreNumbers(u.neighbors)
	u.degeneracy = slices.Max(u.kcore)
	labels := weakComponents(u.neighbors)
	u.weakCount = slices.Max(labels) + 1
	sizes := make([]int, u.weakCount)
	for _, label := range labels {
		sizes[label]++
	}
	u.weakLargest = slices.Max(sizes)
	return u
}
func longestPath(count int, edges []Link) int {
	successors := make([][]int, count)
	pending := make([]int, count)
	for _, edge := range edges {
		successors[edge.source] = append(successors[edge.source], edge.target)
		pending[edge.target]++
	}
	length := make([]int, count)
	ready := []int{}
	for node, value := range pending {
		if value == 0 {
			ready = append(ready, node)
		}
	}
	for len(ready) > 0 {
		node := ready[len(ready)-1]
		ready = ready[:len(ready)-1]
		for _, target := range successors[node] {
			length[target] = max(length[target], length[node]+1)
			pending[target]--
			if pending[target] == 0 {
				ready = append(ready, target)
			}
		}
	}
	return slices.Max(length)
}

type ComponentTable struct {
	groups                             [][]int
	label, incoming, outgoing          []int
	edgeCount, depth, core, singletons int
}

func newComponentTable(g *Graph) *ComponentTable {
	groups := strongComponents(g.successors)
	for _, group := range groups {
		sort.Ints(group)
	}
	sort.Slice(groups, func(i, j int) bool { return groups[i][0] < groups[j][0] })
	t := &ComponentTable{groups: groups, label: make([]int, len(g.pages)), incoming: make([]int, len(groups)), outgoing: make([]int, len(groups))}
	for number, group := range groups {
		for _, node := range group {
			t.label[node] = number
		}
		if len(group) > len(groups[t.core]) {
			t.core = number
		}
		if len(group) == 1 {
			t.singletons++
		}
	}
	set := map[Link]bool{}
	for _, link := range g.links {
		first, second := t.label[link.source], t.label[link.target]
		if first != second {
			t.outgoing[first]++
			t.incoming[second]++
			set[Link{first, second}] = true
		}
	}
	edges := []Link{}
	for edge := range set {
		edges = append(edges, edge)
	}
	t.edgeCount = len(edges)
	t.depth = longestPath(len(groups), edges)
	return t
}
func bowtieRegions(g *Graph, corePages []int) []int {
	forward, backward := reachable(g.successors, corePages), reachable(g.predecessors, corePages)
	inCore := make([]bool, len(g.pages))
	for _, node := range corePages {
		inCore[node] = true
	}
	regions := make([]int, len(g.pages))
	inPages, outPages := []int{}, []int{}
	for node := range regions {
		regions[node] = otherRegion
		if inCore[node] {
			regions[node] = coreRegion
		} else if backward[node] {
			regions[node] = inRegion
			inPages = append(inPages, node)
		} else if forward[node] {
			regions[node] = outRegion
			outPages = append(outPages, node)
		}
	}
	fromIn, toOut := reachable(g.successors, inPages), reachable(g.predecessors, outPages)
	for node := range regions {
		if inCore[node] || backward[node] || forward[node] {
			continue
		}
		if fromIn[node] && toOut[node] {
			regions[node] = tubeRegion
		} else if fromIn[node] {
			regions[node] = inTendril
		} else if toOut[node] {
			regions[node] = outTendril
		}
	}
	return regions
}

type DistanceStats struct {
	pairs, total, diameter int
	source, target         int
	histogram              []int
	harmonic               []float64
}

func newDistanceStats(g *Graph) *DistanceStats {
	d := &DistanceStats{histogram: make([]int, len(g.pages)), harmonic: make([]float64, len(g.pages))}
	for source := range g.pages {
		distance := bfsDistances(g.successors, []int{source})
		for target, steps := range distance {
			if target == source || steps < 0 {
				continue
			}
			d.pairs++
			d.total += steps
			d.histogram[steps]++
			d.harmonic[target] += 1 / float64(steps)
			if steps > d.diameter {
				d.diameter = steps
				d.source = source
				d.target = target
			}
		}
	}
	return d
}
func (d *DistanceStats) effectiveDiameter() int {
	reached := 0
	for steps := 1; steps <= d.diameter; steps++ {
		reached += d.histogram[steps]
		if 10*reached >= 9*d.pairs {
			return steps
		}
	}
	return d.diameter
}

type PageScores struct {
	damping                                                             float64
	pagerankRun, cheirankRun, trustrankRun                              *PageRankResult
	pagerank, cheirank, trustrank, trustRatio, authority, hub, harmonic []float64
	order, rank, cheirankRank, trustDistance                            []int
}

func newPageScores(g *Graph, s Settings, trusted []int, harmonic []float64) *PageScores {
	everyone := sequence(len(g.pages))
	scores := &PageScores{damping: s.damping, harmonic: harmonic}
	scores.pagerankRun = runPageRank(g.forwardEdges(), everyone, s.damping, s)
	scores.cheirankRun = runPageRank(g.reverseEdges(), everyone, s.damping, s)
	scores.trustrankRun = runPageRank(g.forwardEdges(), trusted, s.damping, s)
	scores.pagerank, scores.cheirank, scores.trustrank = scores.pagerankRun.values, scores.cheirankRun.values, scores.trustrankRun.values
	scores.order = rankOrder(scores.pagerank)
	scores.rank = positions(scores.order)
	scores.cheirankRank = positions(rankOrder(scores.cheirank))
	for node, score := range scores.pagerank {
		scores.trustRatio = append(scores.trustRatio, scores.trustrank[node]/score)
	}
	scores.trustDistance = bfsDistances(g.successors, trusted)
	scores.authority, scores.hub = hits(len(g.pages), everyone, g.interHostLinks(g.links), s.hitsIterations)
	return scores
}
func (s *PageScores) contribution(g *Graph, source int) float64 {
	return s.damping * s.pagerank[source] / float64(len(g.successors[source]))
}
func (s *PageScores) representative(nodes []int) int {
	best := nodes[0]
	for _, node := range nodes[1:] {
		if s.rank[node] < s.rank[best] {
			best = node
		}
	}
	return best
}
func scaledValues(values []float64) []int64 {
	result := make([]int64, len(values))
	for i, value := range values {
		result[i] = scaled(value)
	}
	return result
}
func kendall(first, second []int64) string {
	concordant, discordant := 0, 0
	for i := range first {
		for j := i + 1; j < len(first); j++ {
			dx, dy := first[i]-first[j], second[i]-second[j]
			if dx == 0 || dy == 0 {
				continue
			}
			if (dx > 0) == (dy > 0) {
				concordant++
			} else {
				discordant++
			}
		}
	}
	return fraction(concordant-discordant, len(first)*(len(first)-1)/2)
}

type SweepResult struct {
	damping                             float64
	run                                 *PageRankResult
	overlap, footrule, shift, shiftRank int
	correlation                         string
	top                                 []int
}

func newSweep(damping float64, g *Graph, scores *PageScores, s Settings) *SweepResult {
	result := &SweepResult{damping: damping, run: runPageRank(g.forwardEdges(), sequence(len(g.pages)), damping, s)}
	order := rankOrder(result.run.values)
	rank := positions(order)
	for node := range rank {
		if rank[node] <= s.topK && scores.rank[node] <= s.topK {
			result.overlap++
		}
		result.footrule += absInt(rank[node] - scores.rank[node])
		if absInt(rank[node]-scores.rank[node]) > absInt(rank[result.shift]-scores.rank[result.shift]) {
			result.shift = node
		}
	}
	result.correlation = kendall(scaledValues(scores.pagerank), scaledValues(result.run.values))
	result.shiftRank = rank[result.shift]
	result.top = order[:min(s.topK, len(order))]
	return result
}
func absInt(value int) int {
	if value < 0 {
		return -value
	}
	return value
}

type SpamReport struct {
	suspects []int
	hosts    []string
	removed  int
	run      *PageRankResult
	rank     []int
}

func newSpam(g *Graph, scores *PageScores, s Settings) *SpamReport {
	spam := &SpamReport{}
	hosts := map[string]bool{}
	for _, node := range scores.order[:min(s.spamTop, len(scores.order))] {
		if float64(scaled(scores.trustRatio[node], 4))/10000 < s.spamThreshold {
			spam.suspects = append(spam.suspects, node)
			hosts[g.pages[node].host] = true
		}
	}
	for host := range hosts {
		spam.hosts = append(spam.hosts, host)
	}
	sort.Strings(spam.hosts)
	if len(spam.suspects) > 0 {
		kept := []Link{}
		for _, link := range g.links {
			if !(g.intraHost(link) && hosts[g.pages[link.source].host]) {
				kept = append(kept, link)
			}
		}
		spam.removed = len(g.links) - len(kept)
		demoted := newGraph(g.pages, kept)
		spam.run = runPageRank(demoted.forwardEdges(), sequence(len(g.pages)), s.damping, s)
		spam.rank = positions(rankOrder(spam.run.values))
	}
	return spam
}
func titleMatches(words, include, exclude []string) bool {
	for _, word := range include {
		if !slices.Contains(words, word) {
			return false
		}
	}
	for _, word := range exclude {
		if slices.Contains(words, word) {
			return false
		}
	}
	return true
}
func baseMembership(g *Graph, root []int, limit int) []bool {
	inBase := make([]bool, len(g.pages))
	for _, node := range root {
		inBase[node] = true
		for _, next := range g.successors[node][:min(limit, len(g.successors[node]))] {
			inBase[next] = true
		}
		for _, next := range g.predecessors[node][:min(limit, len(g.predecessors[node]))] {
			inBase[next] = true
		}
	}
	return inBase
}
func salsaScores(count int, links []Link) []float64 {
	degree := make([]int, count)
	targets := make([][]int, count)
	for _, link := range links {
		degree[link.target]++
		targets[link.source] = append(targets[link.source], link.target)
	}
	neighbors := make([][]int, count)
	for _, group := range targets {
		for i := 0; i+1 < len(group); i++ {
			first, second := group[i], group[i+1]
			neighbors[first] = append(neighbors[first], second)
			neighbors[second] = append(neighbors[second], first)
		}
	}
	labels := weakComponents(neighbors)
	size, mass := make([]int, count), make([]int, count)
	side := []int{}
	for node, value := range degree {
		if value > 0 {
			side = append(side, node)
			size[labels[node]]++
			mass[labels[node]] += value
		}
	}
	scores := make([]float64, count)
	for _, node := range side {
		label := labels[node]
		scores[node] = float64(size[label]*degree[node]) / float64(len(side)*mass[label])
	}
	return scores
}
func cocitationCounts(g *Graph, page int) []int {
	counts := make([]int, len(g.pages))
	for _, citing := range g.predecessors[page] {
		for _, cited := range g.successors[citing] {
			if cited != page {
				counts[cited]++
			}
		}
	}
	return counts
}
func couplingCounts(g *Graph, page int) []int {
	counts := make([]int, len(g.pages))
	for _, cited := range g.successors[page] {
		for _, citing := range g.predecessors[cited] {
			if citing != page {
				counts[citing]++
			}
		}
	}
	return counts
}
func overlap(first, second []int) int {
	set := map[int]bool{}
	for _, node := range first {
		set[node] = true
	}
	count := 0
	for _, node := range second {
		if set[node] {
			count++
		}
	}
	return count
}

type SubgraphScores struct {
	authority, hub, salsaAuthority, salsaHub                    []float64
	authorityTop, hubTop, salsaAuthorityTop, salsaHubTop        []int
	authorityOverlap, hubOverlap, authorityHosts, cited, citing int
	cocitation, coupling, related, similar                      []int
}

func newSubgraph(g *Graph, base []int, links []Link, s Settings) *SubgraphScores {
	sub := &SubgraphScores{}
	sub.authority, sub.hub = hits(len(g.pages), base, links, s.hitsIterations)
	sub.salsaAuthority = salsaScores(len(g.pages), links)
	reversed := []Link{}
	for _, link := range links {
		reversed = append(reversed, Link{link.target, link.source})
	}
	sub.salsaHub = salsaScores(len(g.pages), reversed)
	sub.authorityTop, sub.hubTop = topList(sub.authority, s.topK), topList(sub.hub, s.topK)
	sub.salsaAuthorityTop, sub.salsaHubTop = topList(sub.salsaAuthority, s.topK), topList(sub.salsaHub, s.topK)
	sub.authorityOverlap, sub.hubOverlap = overlap(sub.authorityTop, sub.salsaAuthorityTop), overlap(sub.hubTop, sub.salsaHubTop)
	hosts := map[string]bool{}
	for _, node := range sub.authorityTop {
		hosts[g.pages[node].host] = true
	}
	sub.authorityHosts = len(hosts)
	sub.cited = sub.authorityTop[0]
	sub.cocitation = cocitationCounts(g, sub.cited)
	sub.related = rankedCounts(sub.cocitation, s.topK)
	sub.citing = sub.hubTop[0]
	sub.coupling = couplingCounts(g, sub.citing)
	sub.similar = rankedCounts(sub.coupling, s.topK)
	return sub
}

type QueryResult struct {
	query                                             Query
	matches                                           []int
	rootSize, baseSize, dropped, reach, globalOverlap int
	subgraph                                          []Link
	personalized                                      *PageRankResult
	seedMass                                          float64
	personalizedTop                                   []int
	scores                                            *SubgraphScores
}

func newQueryResult(query Query, g *Graph, scores *PageScores, s Settings, indexOf map[int]int) *QueryResult {
	result := &QueryResult{query: query}
	include, exclude := []string{}, []string{}
	for _, word := range query.words {
		if strings.HasPrefix(word, "-") {
			exclude = append(exclude, word[1:])
		} else {
			include = append(include, word)
		}
	}
	for _, node := range scores.order {
		if titleMatches(g.pages[node].words, include, exclude) {
			result.matches = append(result.matches, node)
		}
	}
	root := result.matches[:min(s.rootLimit, len(result.matches))]
	result.rootSize = len(root)
	inBase := baseMembership(g, root, s.neighborLimit)
	base := []int{}
	for node, inside := range inBase {
		if inside {
			base = append(base, node)
		}
	}
	result.baseSize = len(base)
	for _, link := range g.links {
		if inBase[link.source] && inBase[link.target] {
			if g.intraHost(link) {
				result.dropped++
			} else {
				result.subgraph = append(result.subgraph, link)
			}
		}
	}
	seeds := []int{}
	for _, id := range query.seeds {
		seeds = append(seeds, indexOf[id])
	}
	sort.Ints(seeds)
	result.personalized = runPageRank(g.forwardEdges(), seeds, s.damping, s)
	for _, seen := range reachable(g.successors, seeds) {
		if seen {
			result.reach++
		}
	}
	for _, node := range seeds {
		result.seedMass += result.personalized.values[node]
	}
	result.personalizedTop = topList(result.personalized.values, s.topK)
	for _, node := range result.personalizedTop {
		if scores.rank[node] <= s.topK {
			result.globalOverlap++
		}
	}
	if len(result.subgraph) > 0 {
		result.scores = newSubgraph(g, base, result.subgraph, s)
	}
	return result
}

type HostGraph struct {
	names                               []string
	ofPage                              []int
	members                             [][]int
	weight                              [][]int
	internal, outgoing, incoming        []int
	edges, heavy                        []Link
	reciprocal, componentCount, largest int
	run                                 *PageRankResult
	rank                                []int
}

func newHostGraph(g *Graph, s Settings) *HostGraph {
	set := map[string]bool{}
	for _, page := range g.pages {
		set[page.host] = true
	}
	h := &HostGraph{}
	for name := range set {
		h.names = append(h.names, name)
	}
	sort.Strings(h.names)
	count := len(h.names)
	index := map[string]int{}
	for i, name := range h.names {
		index[name] = i
	}
	h.ofPage = make([]int, len(g.pages))
	h.members = make([][]int, count)
	h.weight = make([][]int, count)
	h.internal, h.outgoing, h.incoming = make([]int, count), make([]int, count), make([]int, count)
	for i := range h.weight {
		h.weight[i] = make([]int, count)
	}
	for node, page := range g.pages {
		number := index[page.host]
		h.ofPage[node] = number
		h.members[number] = append(h.members[number], node)
	}
	for _, link := range g.links {
		first, second := h.ofPage[link.source], h.ofPage[link.target]
		if first == second {
			h.internal[first]++
		} else {
			h.weight[first][second]++
			h.outgoing[first]++
			h.incoming[second]++
		}
	}
	adjacency := make([][]int, count)
	inEdges := make([][]WeightedEdge, count)
	for first := 0; first < count; first++ {
		for second := 0; second < count; second++ {
			if h.weight[first][second] > 0 {
				edge := Link{first, second}
				h.edges = append(h.edges, edge)
				adjacency[first] = append(adjacency[first], second)
				inEdges[second] = append(inEdges[second], WeightedEdge{first, h.weight[first][second]})
				if h.weight[second][first] > 0 {
					h.reciprocal++
				}
			}
		}
	}
	components := strongComponents(adjacency)
	h.componentCount = len(components)
	for _, group := range components {
		h.largest = max(h.largest, len(group))
	}
	h.run = runPageRank(inEdges, sequence(count), s.damping, s)
	h.rank = positions(rankOrder(h.run.values))
	h.heavy = append([]Link(nil), h.edges...)
	sort.SliceStable(h.heavy, func(i, j int) bool {
		a, b := h.heavy[i], h.heavy[j]
		return h.weight[a.source][a.target] > h.weight[b.source][b.target]
	})
	h.heavy = h.heavy[:min(s.topK, len(h.heavy))]
	return h
}

type Analysis struct {
	input      Input
	graph      *Graph
	ignored    []Ignored
	undirected *Undirected
	components *ComponentTable
	regions    []int
	distances  *DistanceStats
	scores     *PageScores
	sweeps     []*SweepResult
	spam       *SpamReport
	queries    []*QueryResult
	hosts      *HostGraph
}

func newAnalysis(input Input) *Analysis {
	sort.Slice(input.pages, func(i, j int) bool { return input.pages[i].id < input.pages[j].id })
	indexOf := map[int]int{}
	for node, page := range input.pages {
		indexOf[page.id] = node
	}
	links, ignored := classifyLinks(input.records, indexOf)
	a := &Analysis{input: input, graph: newGraph(input.pages, links), ignored: ignored}
	a.undirected = newUndirected(a.graph)
	a.components = newComponentTable(a.graph)
	a.regions = bowtieRegions(a.graph, a.components.groups[a.components.core])
	a.distances = newDistanceStats(a.graph)
	trusted := []int{}
	for _, id := range input.settings.trusted {
		trusted = append(trusted, indexOf[id])
	}
	sort.Ints(trusted)
	a.scores = newPageScores(a.graph, input.settings, trusted, a.distances.harmonic)
	for _, damping := range input.settings.sweep {
		a.sweeps = append(a.sweeps, newSweep(damping, a.graph, a.scores, input.settings))
	}
	a.spam = newSpam(a.graph, a.scores, input.settings)
	for _, query := range input.queries {
		a.queries = append(a.queries, newQueryResult(query, a.graph, a.scores, input.settings, indexOf))
	}
	a.hosts = newHostGraph(a.graph, input.settings)
	return a
}
func (a *Analysis) linkLines() []string {
	g := a.graph
	reasons := map[string]int{}
	for _, ignored := range a.ignored {
		reasons[ignored.reason]++
	}
	intra, reciprocal := 0, 0
	for _, link := range g.links {
		if g.intraHost(link) {
			intra++
		}
		if g.linkSet[Link{link.target, link.source}] {
			reciprocal++
		}
	}
	inDegrees, outDegrees := make([]int, len(g.pages)), make([]int, len(g.pages))
	noIn := []int{}
	for node := range g.pages {
		inDegrees[node] = len(g.predecessors[node])
		outDegrees[node] = len(g.successors[node])
		if inDegrees[node] == 0 {
			noIn = append(noIn, node)
		}
	}
	maxIn, maxOut := slices.Max(inDegrees), slices.Max(outDegrees)
	maxInPages, maxOutPages := []int{}, []int{}
	for node := range g.pages {
		if inDegrees[node] == maxIn {
			maxInPages = append(maxInPages, node)
		}
		if outDegrees[node] == maxOut {
			maxOutPages = append(maxOutPages, node)
		}
	}
	hostSet := map[string]bool{}
	for _, page := range g.pages {
		hostSet[page.host] = true
	}
	lines := []string{fmt.Sprintf("pages %d", len(g.pages)), fmt.Sprintf("hosts %d", len(hostSet)), fmt.Sprintf("link_rows %d", len(a.input.records)), fmt.Sprintf("links %d", len(g.links)), fmt.Sprintf("ignored_unknown %d", reasons["unknown"]), fmt.Sprintf("ignored_self %d", reasons["self"]), fmt.Sprintf("ignored_duplicate %d", reasons["duplicate"])}
	for _, ignored := range a.ignored {
		r := ignored.record
		lines = append(lines, fmt.Sprintf("ignored line %d %d,%d %s", r.line, r.source, r.target, ignored.reason))
	}
	dangling := g.dangling()
	lines = append(lines, fmt.Sprintf("intra_host_links %d", intra), fmt.Sprintf("inter_host_links %d", len(g.links)-intra), "mean_degree "+fixed(float64(len(g.links))/float64(len(g.pages)), 4), "reciprocity "+fraction(reciprocal, len(g.links)))
	appendNodes := func(prefix string, nodes []int) {
		text := prefix
		if len(nodes) > 0 {
			text += " " + integerText(g.ids(nodes))
		}
		lines = append(lines, text)
	}
	appendNodes(fmt.Sprintf("dangling %d", len(dangling)), dangling)
	appendNodes(fmt.Sprintf("no_in_links %d", len(noIn)), noIn)
	appendNodes(fmt.Sprintf("max_in_degree %d pages", maxIn), maxInPages)
	appendNodes(fmt.Sprintf("max_out_degree %d pages", maxOut), maxOutPages)
	lines = append(lines, "", "in_degree_distribution")
	lines = append(lines, distributionLines(inDegrees)...)
	lines = append(lines, "", "out_degree_distribution")
	return append(lines, distributionLines(outDegrees)...)
}
func (a *Analysis) undirectedLines() []string {
	u := a.undirected
	count := 0
	for _, number := range u.kcore {
		if number == u.degeneracy {
			count++
		}
	}
	lines := []string{"", fmt.Sprintf("undirected_links %d", u.edgeCount), "transitivity " + fraction(u.closed, u.possible), fmt.Sprintf("average_clustering %s pages %d", fixed(u.averageClustering, 4), u.eligible), fmt.Sprintf("degeneracy %d pages %d", u.degeneracy, count), "core_distribution"}
	return append(lines, distributionLines(u.kcore)...)
}
func (a *Analysis) componentLines() []string {
	t, u, g := a.components, a.undirected, a.graph
	lines := []string{"", fmt.Sprintf("strong_components %d largest %d singletons %d condensation_links %d", len(t.groups), len(t.groups[t.core]), t.singletons, t.edgeCount), fmt.Sprintf("weak_components %d largest %d", u.weakCount, u.weakLargest), fmt.Sprintf("condensation_depth %d", t.depth)}
	for number, group := range t.groups {
		if len(group) < 2 {
			continue
		}
		scoreSum := 0.0
		for _, node := range group {
			scoreSum += a.scores.pagerank[node]
		}
		text := fmt.Sprintf("scc %d size %d min %d incoming %d outgoing %d pagerank %s", number+1, len(group), g.pages[group[0]].id, t.incoming[number], t.outgoing[number], fixed(scoreSum))
		if t.outgoing[number] == 0 {
			text += " sink"
		}
		lines = append(lines, text)
	}
	return lines
}
func (a *Analysis) bowtieLines() []string {
	g, s := a.graph, a.scores
	lines := []string{"", fmt.Sprintf("bowtie core_scc %d", a.components.core+1)}
	for region, name := range regionNames {
		members := []int{}
		scoreSum := 0.0
		for node, own := range a.regions {
			if own == region {
				members = append(members, node)
				scoreSum += s.pagerank[node]
			}
		}
		text := fmt.Sprintf("%s %d pagerank %s", name, len(members), fixed(scoreSum))
		if len(members) > 0 {
			text += fmt.Sprintf(" top %d", g.pages[s.representative(members)].id)
		}
		if len(members) >= 1 && len(members) <= 10 {
			text += " pages " + integerText(g.ids(members))
		}
		lines = append(lines, text)
	}
	counts := make([][]int, len(regionNames))
	for i := range counts {
		counts[i] = make([]int, len(regionNames))
	}
	for _, link := range g.links {
		counts[a.regions[link.source]][a.regions[link.target]]++
	}
	lines = append(lines, "region_links")
	for first, row := range counts {
		for second, count := range row {
			if count > 0 {
				lines = append(lines, fmt.Sprintf("%s %s %d", regionNames[first], regionNames[second], count))
			}
		}
	}
	return lines
}
func (a *Analysis) distanceLines() []string {
	d, g := a.distances, a.graph
	lines := []string{"", "distances", fmt.Sprintf("reachable_pairs %d", d.pairs), "average " + fraction(d.total, d.pairs), fmt.Sprintf("diameter %d from %d to %d", d.diameter, g.pages[d.source].id, g.pages[d.target].id), fmt.Sprintf("effective_diameter %d", d.effectiveDiameter())}
	for steps := 1; steps <= d.diameter; steps++ {
		lines = append(lines, fmt.Sprintf("%d %d", steps, d.histogram[steps]))
	}
	return lines
}
func (a *Analysis) graphStatsLines() []string {
	lines := a.linkLines()
	lines = append(lines, a.undirectedLines()...)
	lines = append(lines, a.componentLines()...)
	lines = append(lines, a.bowtieLines()...)
	return append(lines, a.distanceLines()...)
}
func (a *Analysis) pagerankCSVLines() []string {
	g, s := a.graph, a.scores
	lines := []string{"id,in_degree,out_degree,scc,region,kcore,harmonic,pagerank,pagerank_rank,cheirank,cheirank_rank,authority,hub,trustrank,trust_ratio,trust_distance"}
	for node, page := range g.pages {
		fields := []string{strconv.Itoa(page.id), strconv.Itoa(len(g.predecessors[node])), strconv.Itoa(len(g.successors[node])), strconv.Itoa(a.components.label[node] + 1), regionNames[a.regions[node]], strconv.Itoa(a.undirected.kcore[node]), fixed(s.harmonic[node]), fixed(s.pagerank[node]), strconv.Itoa(s.rank[node]), fixed(s.cheirank[node]), strconv.Itoa(s.cheirankRank[node]), fixed(s.authority[node]), fixed(s.hub[node]), fixed(s.trustrank[node]), fixed(s.trustRatio[node], 4), strconv.Itoa(s.trustDistance[node])}
		lines = append(lines, strings.Join(fields, ","))
	}
	return lines
}
func rankLines(g *Graph, nodes []int, values []float64) []string {
	lines := []string{}
	for i, node := range nodes {
		lines = append(lines, g.describe(i+1, node, fixed(values[node])))
	}
	return lines
}
func scoreBlock(name string, g *Graph, values []float64, limit int) []string {
	return append([]string{fmt.Sprintf("%s top %d", name, limit)}, rankLines(g, topList(values, limit), values)...)
}
func (a *Analysis) pagerankBlock() []string {
	g, s, limit := a.graph, a.scores, a.input.settings.topK
	top := topList(s.pagerank, limit)
	lines := scoreBlock("pagerank", g, s.pagerank, limit)
	mass := 0.0
	for _, node := range g.dangling() {
		mass += s.pagerank[node]
	}
	lines = append(lines, "dangling_mass "+fixed(mass))
	for _, node := range top {
		contributors := append([]int(nil), g.predecessors[node]...)
		sort.SliceStable(contributors, func(i, j int) bool {
			return scaled(s.contribution(g, contributors[i])) > scaled(s.contribution(g, contributors[j]))
		})
		parts := []string{"contributors", strconv.Itoa(g.pages[node].id)}
		for _, source := range contributors[:min(3, len(contributors))] {
			parts = append(parts, strconv.Itoa(g.pages[source].id), fixed(s.contribution(g, source)))
		}
		lines = append(lines, strings.Join(parts, " "))
	}
	return lines
}
func (a *Analysis) correlationBlock() []string {
	g, s := a.graph, a.scores
	inDegrees := make([]int64, len(g.pages))
	for node, sources := range g.predecessors {
		inDegrees[node] = int64(len(sources))
	}
	series := [][]int64{inDegrees, scaledValues(s.pagerank), scaledValues(s.cheirank), scaledValues(s.authority), scaledValues(s.hub), scaledValues(s.trustrank), scaledValues(s.harmonic)}
	lines := []string{"correlation"}
	for first, name := range quantityNames {
		for second := first + 1; second < len(quantityNames); second++ {
			lines = append(lines, name+" "+quantityNames[second]+" "+kendall(series[first], series[second]))
		}
	}
	return lines
}
func (a *Analysis) sweepBlock() []string {
	g, s := a.graph, a.scores
	lines := []string{"damping_sweep"}
	for _, sweep := range a.sweeps {
		lines = append(lines, fmt.Sprintf("damping %s overlap %d footrule %d kendall %s largest_shift %d %d %d", fixed(sweep.damping, 4), sweep.overlap, sweep.footrule, sweep.correlation, g.pages[sweep.shift].id, s.rank[sweep.shift], sweep.shiftRank), "top "+integerText(g.ids(sweep.top)))
	}
	return lines
}
func (a *Analysis) spamBlock() []string {
	g, s, settings := a.graph, a.scores, a.input.settings
	lines := []string{fmt.Sprintf("spam top %d threshold %s", settings.spamTop, fixed(settings.spamThreshold, 4))}
	for _, node := range a.spam.suspects {
		lines = append(lines, fmt.Sprintf("suspect %d rank %d pagerank %s trustrank %s trust_ratio %s trust_distance %d kcore %d %s", g.pages[node].id, s.rank[node], fixed(s.pagerank[node]), fixed(s.trustrank[node]), fixed(s.trustRatio[node], 4), s.trustDistance[node], a.undirected.kcore[node], g.pages[node].host))
	}
	lines = append(lines, fmt.Sprintf("count %d", len(a.spam.suspects)), "trust_by_distance")
	set := map[int]bool{}
	for _, distance := range s.trustDistance {
		set[distance] = true
	}
	distances := []int{}
	for distance := range set {
		if distance >= 0 {
			distances = append(distances, distance)
		}
	}
	sort.Ints(distances)
	if set[-1] {
		distances = append(distances, -1)
	}
	for _, distance := range distances {
		count := 0
		trust, rank := 0.0, 0.0
		for node, own := range s.trustDistance {
			if own == distance {
				count++
				trust += s.trustrank[node]
				rank += s.pagerank[node]
			}
		}
		name := strconv.Itoa(distance)
		if distance < 0 {
			name = "unreachable"
		}
		lines = append(lines, fmt.Sprintf("%s pages %d trustrank %s pagerank %s", name, count, fixed(trust), fixed(rank)))
	}
	return lines
}
func (a *Analysis) demotionBlock() []string {
	spam, g, s := a.spam, a.graph, a.scores
	if len(spam.suspects) == 0 {
		return []string{"demotion none"}
	}
	lines := []string{fmt.Sprintf("demotion hosts %s removed_links %d", strings.Join(spam.hosts, " "), spam.removed)}
	for i, node := range topList(spam.run.values, a.input.settings.topK) {
		lines = append(lines, g.describe(i+1, node, fixed(spam.run.values[node]), "was", strconv.Itoa(s.rank[node])))
	}
	for _, node := range spam.suspects {
		lines = append(lines, fmt.Sprintf("suspect %d before %d after %d", g.pages[node].id, s.rank[node], spam.rank[node]))
	}
	return lines
}
func (a *Analysis) hostGraphBlock() []string {
	h := a.hosts
	lines := []string{fmt.Sprintf("host_graph hosts %d links %d reciprocal %d strong_components %d largest %d", len(h.names), len(h.edges), h.reciprocal, h.componentCount, h.largest), fmt.Sprintf("host_links top %d", a.input.settings.topK)}
	for _, edge := range h.heavy {
		lines = append(lines, fmt.Sprintf("%s %s %d", h.names[edge.source], h.names[edge.target], h.weight[edge.source][edge.target]))
	}
	return lines
}
func (a *Analysis) rankingsLines() []string {
	g, s, k := a.graph, a.scores, a.input.settings.topK
	return joinBlocks([][]string{a.pagerankBlock(), scoreBlock("cheirank", g, s.cheirank, k), scoreBlock("authority", g, s.authority, k), scoreBlock("hub", g, s.hub, k), scoreBlock("trustrank", g, s.trustrank, k), scoreBlock("harmonic", g, s.harmonic, k), a.correlationBlock(), a.sweepBlock(), a.spamBlock(), a.demotionBlock(), a.hostGraphBlock()})
}
func convergenceBlock(heading string, run *PageRankResult) []string {
	lines := []string{"", heading}
	for step := 10; step <= len(run.changes); step += 10 {
		lines = append(lines, fmt.Sprintf("iteration %d l1 %s", step, fixed(run.changes[step-1], 10)))
	}
	point := "none"
	if run.convergedAt > 0 {
		point = strconv.Itoa(run.convergedAt)
	}
	return append(lines, "converged_at "+point)
}
func (a *Analysis) convergenceLines() []string {
	s, settings := a.scores, a.input.settings
	damping := fixed(settings.damping, 4)
	lines := []string{fmt.Sprintf("iterations %d tolerance %s", settings.iterations, fixed(settings.tolerance, 10))}
	lines = append(lines, convergenceBlock("pagerank damping "+damping, s.pagerankRun)...)
	lines = append(lines, convergenceBlock("cheirank damping "+damping, s.cheirankRun)...)
	lines = append(lines, convergenceBlock(fmt.Sprintf("trustrank damping %s seeds %d", damping, len(settings.trusted)), s.trustrankRun)...)
	for _, sweep := range a.sweeps {
		lines = append(lines, convergenceBlock("sweep damping "+fixed(sweep.damping, 4), sweep.run)...)
	}
	if a.spam.run != nil {
		lines = append(lines, convergenceBlock("demoted damping "+damping, a.spam.run)...)
	}
	for _, result := range a.queries {
		lines = append(lines, convergenceBlock(fmt.Sprintf("personalized query %d damping %s", result.query.number, damping), result.personalized)...)
	}
	return append(lines, convergenceBlock(fmt.Sprintf("host_pagerank damping %s hosts %d", damping, len(a.hosts.names)), a.hosts.run)...)
}
func (a *Analysis) queryBlock(result *QueryResult) []string {
	g, s, limit := a.graph, a.scores, a.input.settings.topK
	q := result.query
	lines := []string{fmt.Sprintf("query %d words %s seeds %s", q.number, strings.Join(q.words, " "), integerText(q.seeds)), fmt.Sprintf("matched %d root %d base %d links %d dropped_intra_host %d", len(result.matches), result.rootSize, result.baseSize, len(result.subgraph), result.dropped), "results"}
	lines = append(lines, rankLines(g, result.matches[:min(limit, len(result.matches))], s.pagerank)...)
	lines = append(lines, fmt.Sprintf("personalized reach %d seed_mass %s", result.reach, fixed(result.seedMass)))
	lines = append(lines, rankLines(g, result.personalizedTop, result.personalized.values)...)
	lines = append(lines, fmt.Sprintf("overlap_with_global %d", result.globalOverlap))
	sub := result.scores
	if sub == nil {
		return append(lines, "hits none")
	}
	for _, part := range []struct {
		heading string
		nodes   []int
		values  []float64
	}{{"hits authorities", sub.authorityTop, sub.authority}, {"hits hubs", sub.hubTop, sub.hub}, {"salsa authorities", sub.salsaAuthorityTop, sub.salsaAuthority}, {"salsa hubs", sub.salsaHubTop, sub.salsaHub}} {
		lines = append(lines, part.heading)
		lines = append(lines, rankLines(g, part.nodes, part.values)...)
	}
	lines = append(lines, fmt.Sprintf("hits_salsa_overlap authorities %d hubs %d authority_hosts %d", sub.authorityOverlap, sub.hubOverlap, sub.authorityHosts), fmt.Sprintf("related_to %d citing %d", g.pages[sub.cited].id, len(g.predecessors[sub.cited])))
	for i, node := range sub.related {
		lines = append(lines, g.describe(i+1, node, strconv.Itoa(sub.cocitation[node])))
	}
	lines = append(lines, fmt.Sprintf("coupled_to %d cited %d", g.pages[sub.citing].id, len(g.successors[sub.citing])))
	for i, node := range sub.similar {
		lines = append(lines, g.describe(i+1, node, strconv.Itoa(sub.coupling[node])))
	}
	return lines
}
func (a *Analysis) queriesLines() []string {
	blocks := [][]string{}
	for _, result := range a.queries {
		blocks = append(blocks, a.queryBlock(result))
	}
	return joinBlocks(blocks)
}
func (a *Analysis) hostsCSVLines() []string {
	g, s, h := a.graph, a.scores, a.hosts
	lines := []string{"host,pages,core_pages,internal_links,internal_density,outgoing_links,incoming_links,dangling_pages,page_score_sum,top_page,score,rank"}
	for number, name := range h.names {
		members := h.members[number]
		size := len(members)
		density := 0.0
		if size >= 2 {
			density = float64(h.internal[number]) / float64(size*(size-1))
		}
		core, dangling := 0, 0
		sum := 0.0
		for _, node := range members {
			if a.regions[node] == coreRegion {
				core++
			}
			if len(g.successors[node]) == 0 {
				dangling++
			}
			sum += s.pagerank[node]
		}
		fields := []string{name, strconv.Itoa(size), strconv.Itoa(core), strconv.Itoa(h.internal[number]), fixed(density, 4), strconv.Itoa(h.outgoing[number]), strconv.Itoa(h.incoming[number]), strconv.Itoa(dangling), fixed(sum), strconv.Itoa(g.pages[s.representative(members)].id), fixed(h.run.values[number]), strconv.Itoa(h.rank[number])}
		lines = append(lines, strings.Join(fields, ","))
	}
	return lines
}
func main() {
	analysis := newAnalysis(readInput())
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	files := []struct {
		name  string
		lines []string
	}{{"graph_stats.txt", analysis.graphStatsLines()}, {"pagerank.csv", analysis.pagerankCSVLines()}, {"rankings.txt", analysis.rankingsLines()}, {"convergence.txt", analysis.convergenceLines()}, {"queries.txt", analysis.queriesLines()}, {"hosts.csv", analysis.hostsCSVLines()}}
	for _, file := range files {
		writeLines(file.name, file.lines)
	}
}
