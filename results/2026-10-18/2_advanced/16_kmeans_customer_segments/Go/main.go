package main

import (
	"fmt"
	"math"
	"os"
	"sort"
	"strconv"
	"strings"
)

type Minstd struct{ state int64 }

func (g *Minstd) draw() int64 {
	g.state = 48271 * g.state % 2147483647
	return g.state
}
func nearestGaps(points [][]float64, chosen []int) []float64 {
	gaps := make([]float64, len(points))
	for i, point := range points {
		gaps[i] = squaredDistance(point, points[chosen[0]])
		for _, index := range chosen[1:] {
			gaps[i] = min(gaps[i], squaredDistance(point, points[index]))
		}
	}
	return gaps
}
func maximin(points [][]float64, k, number int) []int {
	center := meanPoint(points)
	spread := make([]float64, len(points))
	order := make([]int, len(points))
	for i, point := range points {
		spread[i] = squaredDistance(point, center)
		order[i] = i
	}
	sort.SliceStable(order, func(i, j int) bool { return spread[order[i]] < spread[order[j]] })
	chosen := []int{order[number-1]}
	for len(chosen) < k {
		gaps := nearestGaps(points, chosen)
		best := 0
		for i := 1; i < len(gaps); i++ {
			if gaps[i] > gaps[best] {
				best = i
			}
		}
		chosen = append(chosen, best)
	}
	return chosen
}
func initialSeeds(method string, points [][]float64, k, number int, generator *Minstd) []int {
	if method == "maximin" {
		return maximin(points, k, number)
	}
	chosen := []int{}
	if method == "forgy" {
		seen := map[int]bool{}
		for len(chosen) < k {
			index := int(generator.draw() % int64(len(points)))
			if !seen[index] {
				seen[index] = true
				chosen = append(chosen, index)
			}
		}
		return chosen
	}
	chosen = append(chosen, int(generator.draw()%int64(len(points))))
	for len(chosen) < k {
		gaps := nearestGaps(points, chosen)
		weight := orderedSum(gaps)
		threshold := (float64(generator.draw()) / 2147483647) * weight
		total := 0.0
		selected := -1
		for i, gap := range gaps {
			total += gap
			if total > threshold {
				selected = i
				break
			}
		}
		if selected < 0 {
			for i, gap := range gaps {
				if gap > 0 {
					selected = i
				}
			}
		}
		chosen = append(chosen, selected)
	}
	return chosen
}

type Improvement struct {
	labels            []int
	passes, transfers int
	sse               float64
}

func improve(points [][]float64, original []int, k, limit int) Improvement {
	labels := append([]int(nil), original...)
	sizes := clusterSizes(labels, k)
	centers := clusterCenters(points, labels, k)
	passes, transfers := 0, 0
	for passes < limit {
		moved := false
		passes++
		for i, point := range points {
			own := labels[i]
			if sizes[own] == 1 {
				continue
			}
			removal := (float64(sizes[own]) / float64(sizes[own]-1)) * squaredDistance(point, centers[own])
			target := -1
			cost := 0.0
			for q := 0; q < k; q++ {
				if q == own {
					continue
				}
				candidate := (float64(sizes[q]) / float64(sizes[q]+1)) * squaredDistance(point, centers[q])
				if target < 0 || candidate < cost {
					target = q
					cost = candidate
				}
			}
			if cost < removal {
				labels[i] = target
				sizes[own]--
				sizes[target]++
				centers[own] = clusterCenter(points, labels, own)
				centers[target] = clusterCenter(points, labels, target)
				transfers++
				moved = true
			}
		}
		if !moved {
			break
		}
	}
	return Improvement{labels, passes, transfers, sse(points, labels, clusterCenters(points, labels, k))}
}

type Run struct {
	method   string
	number   int
	seeds    []int
	lloyd    LloydResult
	lloydSSE float64
	improved Improvement
}

func newRun(method string, number int, seeds []int, points [][]float64, limit int) *Run {
	initial := [][]float64{}
	for _, index := range seeds {
		initial = append(initial, points[index])
	}
	result := lloyd(points, initial, limit)
	return &Run{method, number, seeds, result, sse(points, result.labels, result.centers), improve(points, result.labels, len(seeds), limit)}
}
func bestRun(runs []*Run) *Run {
	best := runs[0]
	for _, run := range runs[1:] {
		if fourDecimal(run.improved.sse) < fourDecimal(best.improved.sse) {
			best = run
		}
	}
	return best
}

type Solution struct {
	k             int
	members       [][]int
	sizes, labels []int
	centers       [][]float64
	sse           float64
}

func newSolution(points [][]float64, labels []int, k int) Solution {
	groups := make([][]int, k)
	for i, label := range labels {
		groups[label] = append(groups[label], i)
	}
	sort.Slice(groups, func(i, j int) bool {
		if len(groups[i]) != len(groups[j]) {
			return len(groups[i]) > len(groups[j])
		}
		return groups[i][0] < groups[j][0]
	})
	updated := make([]int, len(labels))
	sizes := make([]int, k)
	for j, group := range groups {
		sizes[j] = len(group)
		for _, i := range group {
			updated[i] = j
		}
	}
	centers := clusterCenters(points, updated, k)
	return Solution{k, groups, sizes, updated, centers, sse(points, updated, centers)}
}

type Candidate struct {
	k                                                  int
	runs, methodBests                                  []*Run
	best                                               *Run
	solution                                           Solution
	silhouettes                                        []float64
	silhouette, calinskiHarabasz, daviesBouldin, elbow float64
	hartigan                                           *float64
	ruleNumbers                                        []int
	names                                              []string
}

func segmentNames(rules []Rule, centers [][]float64) ([]int, []string) {
	numbers, names := []int{}, []string{}
	used := map[int]int{}
	for _, center := range centers {
		number := ruleNumber(rules, center)
		used[number]++
		name := rules[number-1].name
		if used[number] > 1 {
			name += fmt.Sprintf("_%d", used[number])
		}
		numbers = append(numbers, number)
		names = append(names, name)
	}
	return numbers, names
}
func rfmScores(customers []*Customer) [][]int {
	scores := make([][]int, len(customers))
	for i, c := range customers {
		ranks := []int{0, 0, 0}
		for _, other := range customers {
			if other.recency > c.recency {
				ranks[0]++
			}
			if other.frequency < c.frequency {
				ranks[1]++
			}
			if other.spend < c.spend {
				ranks[2]++
			}
		}
		scores[i] = []int{}
		for _, rank := range ranks {
			scores[i] = append(scores[i], 1+5*rank/len(customers))
		}
	}
	return scores
}
func gini(spends []int64) float64 {
	ordered := append([]int64(nil), spends...)
	sort.Slice(ordered, func(i, j int) bool { return ordered[i] < ordered[j] })
	total, weighted := int64(0), int64(0)
	for i, spend := range ordered {
		total += spend
		weighted += int64(i+1) * spend
	}
	count := int64(len(spends))
	return float64(2*weighted-(count+1)*total) / float64(count*total)
}
func lowerMedian(values []float64) float64 {
	ordered := append([]float64(nil), values...)
	sort.Float64s(ordered)
	return ordered[(len(ordered)-1)/2]
}
func traits(center []float64) []string {
	order := make([]int, len(center))
	for i := range order {
		order[i] = i
	}
	sort.SliceStable(order, func(i, j int) bool { return math.Abs(center[order[i]]) > math.Abs(center[order[j]]) })
	names := []string{}
	for _, f := range order[:2] {
		prefix := "low_"
		if center[f] > 0 {
			prefix = "high_"
		}
		names = append(names, prefix+featureNames[f])
	}
	return names
}
func categoryTotals(customers []*Customer) map[string]int64 {
	totals := map[string]int64{}
	for _, customer := range customers {
		for category, spend := range customer.categorySpend {
			totals[category] += spend
		}
	}
	return totals
}
func categoryRanking(totals map[string]int64) []string {
	names := []string{}
	for category, spend := range totals {
		if spend > 0 {
			names = append(names, category)
		}
	}
	sort.Slice(names, func(i, j int) bool {
		if totals[names[i]] != totals[names[j]] {
			return totals[names[i]] > totals[names[j]]
		}
		return names[i] < names[j]
	})
	return names
}
func yesNo(flag bool) string {
	if flag {
		return "yes"
	}
	return "no"
}
func integers(values []int) string {
	fields := []string{}
	for _, value := range values {
		fields = append(fields, strconv.Itoa(value))
	}
	return strings.Join(fields, " ")
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

type Other struct {
	segment  int
	distance float64
}
type Vote struct {
	criterion string
	k         int
}
type Analysis struct {
	params                 Params
	data                   TransactionData
	rules                  []Rule
	generator              Minstd
	referenceOrders        []*Order
	customerOrders         map[string][]*Order
	customers              []*Customer
	numbers                map[string]int
	means, sds             []float64
	points                 [][]float64
	candidates             []*Candidate
	votes                  []Vote
	final                  *Candidate
	finalVotes, k          int
	labels                 []int
	centers                [][]float64
	names                  []string
	silhouettes, distances []float64
	others                 []Other
	scores                 [][]int
	codes                  []string
	totalSpend             int64
	overallCategories      map[string]int64
	categoryNames          []string
	segmentCustomers       [][]*Customer
	segmentSpends          []int64
	segmentCategories      []map[string]int64
	rankings               [][]string
	segmentSSE             []float64
	jaccards               [][]float64
}

func newAnalysis(p Params, data TransactionData, rules []Rule) *Analysis {
	a := &Analysis{params: p, data: data, rules: rules, generator: Minstd{p.seed}, numbers: map[string]int{}}
	a.referenceOrders = groupOrders(data.validRows, 1, p.referenceDay)
	a.customerOrders = ordersByCustomer(a.referenceOrders)
	a.customers = eligibleCustomers(a.referenceOrders, p.referenceDay)
	transformed := [][]float64{}
	for i, c := range a.customers {
		a.numbers[c.id] = i
		transformed = append(transformed, c.transformed())
	}
	a.means, a.sds = standardization(transformed)
	for _, values := range transformed {
		a.points = append(a.points, standardize(values, a.means, a.sds))
	}
	return a
}
func (a *Analysis) ids(numbers []int) string {
	ids := []string{}
	for _, i := range numbers {
		ids = append(ids, a.customers[i].id)
	}
	return strings.Join(ids, " ")
}
func (a *Analysis) candidate(k int) *Candidate { return a.candidates[k-a.params.kMin] }
func (a *Analysis) search(k int) *Candidate {
	runs, bests := []*Run{}, []*Run{}
	for _, method := range a.params.methods {
		methodRuns := []*Run{}
		for number := 1; number <= a.params.restarts; number++ {
			seeds := initialSeeds(method, a.points, k, number, &a.generator)
			methodRuns = append(methodRuns, newRun(method, number, seeds, a.points, a.params.maxIterations))
		}
		runs = append(runs, methodRuns...)
		bests = append(bests, bestRun(methodRuns))
	}
	best := bestRun(bests)
	return &Candidate{k: k, runs: runs, methodBests: bests, best: best, solution: newSolution(a.points, best.improved.labels, k)}
}
func (a *Analysis) evaluate() {
	table := distanceTable(a.points)
	first, last := a.candidates[0].solution.sse, a.candidates[len(a.candidates)-1].solution.sse
	for position, c := range a.candidates {
		s := c.solution
		c.silhouettes = silhouettes(table, s.labels, s.sizes)
		c.silhouette = mean(c.silhouettes)
		c.calinskiHarabasz = calinskiHarabasz(a.points, s.centers, s.sizes, s.sse)
		c.daviesBouldin = daviesBouldin(a.points, s.labels, s.centers, s.sizes)
		c.elbow = elbow(c.k, a.params.kMin, a.params.kMax, s.sse, first, last)
		if c.k < a.params.kMax {
			value := hartigan(s.sse, a.candidates[position+1].solution.sse, len(a.points), c.k)
			c.hartigan = &value
		}
		c.ruleNumbers, c.names = segmentNames(a.rules, s.centers)
	}
}
func (a *Analysis) chooseK() {
	functions := []func(*Candidate) float64{func(c *Candidate) float64 { return c.elbow }, func(c *Candidate) float64 { return c.silhouette }, func(c *Candidate) float64 { return c.calinskiHarabasz }, func(c *Candidate) float64 { return -c.daviesBouldin }}
	criteria := []string{"elbow", "silhouette", "calinski_harabasz", "davies_bouldin"}
	counts := map[int]int{}
	for column, function := range functions {
		candidates := a.candidates
		if column == 0 {
			candidates = candidates[1 : len(candidates)-1]
		}
		best := candidates[0]
		for _, c := range candidates[1:] {
			if fourDecimal(function(c)) > fourDecimal(function(best)) {
				best = c
			}
		}
		a.votes = append(a.votes, Vote{criteria[column], best.k})
		counts[best.k]++
	}
	chosen := a.params.kMax
	for _, c := range a.candidates {
		if c.hartigan != nil && *c.hartigan <= 10 {
			chosen = c.k
			break
		}
	}
	a.votes = append(a.votes, Vote{"hartigan", chosen})
	counts[chosen]++
	a.final = a.candidates[0]
	for _, c := range a.candidates[1:] {
		if counts[c.k] > counts[a.final.k] || counts[c.k] == counts[a.final.k] && fourDecimal(c.silhouette) > fourDecimal(a.final.silhouette) {
			a.final = c
		}
	}
	a.finalVotes = counts[a.final.k]
}
func (a *Analysis) describeFinal() {
	s := a.final.solution
	a.k = s.k
	a.labels = s.labels
	a.centers = s.centers
	a.names = a.final.names
	a.silhouettes = a.final.silhouettes
	for i, point := range a.points {
		label := a.labels[i]
		other := -1
		best := 0.0
		for j, center := range a.centers {
			if j == label {
				continue
			}
			distance := squaredDistance(point, center)
			if other < 0 || distance < best {
				other = j
				best = distance
			}
		}
		a.distances = append(a.distances, math.Sqrt(squaredDistance(point, a.centers[label])))
		a.others = append(a.others, Other{other, math.Sqrt(best)})
	}
	a.scores = rfmScores(a.customers)
	for _, score := range a.scores {
		a.codes = append(a.codes, fmt.Sprintf("%d%d%d", score[0], score[1], score[2]))
	}
	for _, c := range a.customers {
		a.totalSpend += c.spend
	}
	a.overallCategories = categoryTotals(a.customers)
	for name := range a.overallCategories {
		a.categoryNames = append(a.categoryNames, name)
	}
	sort.Strings(a.categoryNames)
	for j, members := range s.members {
		customers := []*Customer{}
		spend := int64(0)
		total := 0.0
		for _, i := range members {
			customers = append(customers, a.customers[i])
			spend += a.customers[i].spend
			total += squaredDistance(a.points[i], a.centers[j])
		}
		a.segmentCustomers = append(a.segmentCustomers, customers)
		a.segmentSpends = append(a.segmentSpends, spend)
		categories := categoryTotals(customers)
		a.segmentCategories = append(a.segmentCategories, categories)
		a.rankings = append(a.rankings, categoryRanking(categories))
		a.segmentSSE = append(a.segmentSSE, total)
	}
}
func (a *Analysis) analyze() {
	for k := a.params.kMin; k <= a.params.kMax; k++ {
		a.candidates = append(a.candidates, a.search(k))
	}
	a.evaluate()
	a.chooseK()
	a.describeFinal()
	a.jaccards = a.subsampleJaccards()
}
func (a *Analysis) recommendation(number int) string {
	c := a.customers[number]
	for _, category := range a.rankings[a.labels[number]] {
		if c.categorySpend[category] <= 0 {
			return category
		}
	}
	return "-"
}
func (a *Analysis) subsampleJaccards() [][]float64 {
	n := len(a.points)
	size := n * a.params.subsamplePercent / 100
	jaccards := make([][]float64, a.k)
	for b := 0; b < a.params.subsamples; b++ {
		order := make([]int, n)
		for i := range order {
			order[i] = i
		}
		for t := 0; t < size; t++ {
			j := t + int(a.generator.draw()%int64(n-t))
			order[t], order[j] = order[j], order[t]
		}
		sample := append([]int(nil), order[:size]...)
		sort.Ints(sample)
		points := [][]float64{}
		for _, i := range sample {
			points = append(points, a.points[i])
		}
		result := lloyd(points, a.centers, a.params.maxIterations)
		for segment := 0; segment < a.k; segment++ {
			best := 0.0
			for j := 0; j < a.k; j++ {
				both, either := 0, 0
				for i, number := range sample {
					member := a.labels[number] == segment
					actual := result.labels[i] == j
					if member && actual {
						both++
					}
					if member || actual {
						either++
					}
				}
				if either > 0 {
					best = max(best, float64(both)/float64(either))
				}
			}
			jaccards[segment] = append(jaccards[segment], best)
		}
	}
	return jaccards
}
func (a *Analysis) featuresLines() []string {
	lines := []string{"customer,recency,frequency,monetary,basket,categories,tenure,z_recency,z_frequency,z_monetary,z_basket,z_categories,z_tenure"}
	for i, c := range a.customers {
		fields := []string{c.id, strconv.Itoa(c.recency), strconv.Itoa(c.frequency), amount(c.spend), realText(c.basket), strconv.Itoa(c.categories), strconv.Itoa(c.tenure)}
		for _, value := range a.points[i] {
			fields = append(fields, realText(value))
		}
		lines = append(lines, strings.Join(fields, ","))
	}
	return lines
}
func (a *Analysis) runLine(run *Run) string {
	return fmt.Sprintf("run %s %d seeds %s iterations %d converged %s reseeds %d sse %s passes %d transfers %d refined %s", run.method, run.number, a.ids(run.seeds), run.lloyd.iterations, yesNo(run.lloyd.converged), run.lloyd.reseeds, realText(run.lloydSSE), run.improved.passes, run.improved.transfers, realText(run.improved.sse))
}
func runSummary(run *Run) string {
	return fmt.Sprintf("%s restart %d sse %s", run.method, run.number, realText(run.improved.sse))
}
func (a *Analysis) runsLines() []string {
	blocks := [][]string{}
	for _, c := range a.candidates {
		lines := []string{fmt.Sprintf("k %d", c.k)}
		for _, run := range c.runs {
			lines = append(lines, a.runLine(run))
		}
		for _, run := range c.methodBests {
			lines = append(lines, "best "+runSummary(run))
		}
		lines = append(lines, "chosen "+runSummary(c.best), "sizes "+integers(c.solution.sizes))
		blocks = append(blocks, lines)
	}
	return joinBlocks(blocks)
}
func (a *Analysis) stabilityLine(position int, c *Candidate) string {
	parts := []string{fmt.Sprintf("k=%d", c.k)}
	for i, first := range c.methodBests {
		for _, second := range c.methodBests[i+1:] {
			parts = append(parts, first.method+":"+second.method, realText(adjustedRand(first.improved.labels, second.improved.labels)))
		}
	}
	parts = append(parts, "final")
	for _, run := range c.methodBests {
		parts = append(parts, run.method, realText(adjustedRand(run.improved.labels, c.solution.labels)))
	}
	following := "-"
	if position+1 < len(a.candidates) {
		following = realText(adjustedRand(c.solution.labels, a.candidates[position+1].solution.labels))
	}
	return strings.Join(append(parts, "next", following), " ")
}
func (a *Analysis) selectionLines() []string {
	indices, votes, names, stability := []string{"indices"}, []string{"votes"}, []string{"segments"}, []string{"stability"}
	for i, c := range a.candidates {
		h := "-"
		if c.hartigan != nil {
			h = realText(*c.hartigan)
		}
		indices = append(indices, fmt.Sprintf("k=%d sse %s elbow %s silhouette %s calinski_harabasz %s davies_bouldin %s hartigan %s", c.k, realText(c.solution.sse), realText(c.elbow), realText(c.silhouette), realText(c.calinskiHarabasz), realText(c.daviesBouldin), h))
		parts := []string{fmt.Sprintf("k=%d", c.k)}
		for j, name := range c.names {
			parts = append(parts, fmt.Sprintf("%s:%d", name, c.solution.sizes[j]))
		}
		names = append(names, strings.Join(parts, " "))
		stability = append(stability, a.stabilityLine(i, c))
	}
	for _, vote := range a.votes {
		votes = append(votes, fmt.Sprintf("%s k=%d", vote.criterion, vote.k))
	}
	votes = append(votes, fmt.Sprintf("chosen k=%d votes %d", a.final.k, a.finalVotes))
	return joinBlocks([][]string{indices, votes, names, stability})
}
func (a *Analysis) segmentsLines() []string {
	lines := []string{"customer,segment,name,distance,other,other_distance,silhouette,recommend"}
	for i, c := range a.customers {
		label, other := a.labels[i], a.others[i]
		lines = append(lines, strings.Join([]string{c.id, strconv.Itoa(label + 1), a.names[label], realText(a.distances[i]), strconv.Itoa(other.segment + 1), realText(other.distance), realText(a.silhouettes[i]), a.recommendation(i)}, ","))
	}
	return lines
}
func (a *Analysis) medianLine(customers []*Customer) string {
	values := make([][]float64, 6)
	for _, c := range customers {
		for f, value := range c.values() {
			if f == 2 {
				value = float64(c.spend)
			}
			values[f] = append(values[f], value)
		}
	}
	medians := make([]float64, 6)
	for f := range medians {
		medians[f] = lowerMedian(values[f])
	}
	return fmt.Sprintf("  median recency %.0f frequency %.0f monetary %s basket %s categories %.0f tenure %.0f", medians[0], medians[1], amount(int64(medians[2])), realText(medians[3]), medians[4], medians[5])
}
func (a *Analysis) related(members []int, k int) string {
	if k < a.params.kMin || k > a.params.kMax {
		return fmt.Sprintf("k=%d -", k)
	}
	counts := make([]int, k)
	labels := a.candidate(k).solution.labels
	for _, i := range members {
		counts[labels[i]]++
	}
	best := 0
	for j := 1; j < k; j++ {
		if counts[j] > counts[best] {
			best = j
		}
	}
	return fmt.Sprintf("k=%d segment %d shared %d", k, best+1, counts[best])
}
func (a *Analysis) cadenceLine(customers []*Customer) string {
	gaps := []float64{}
	overdue := 0
	for _, c := range customers {
		if c.frequency < 2 {
			continue
		}
		active, intervals := c.tenure-c.recency, c.frequency-1
		gaps = append(gaps, float64(active)/float64(intervals))
		if c.recency*intervals > a.params.overdueFactor*active {
			overdue++
		}
	}
	text := "-"
	if len(gaps) > 0 {
		text = realText(mean(gaps))
	}
	return fmt.Sprintf("  cadence customers %d mean_gap %s overdue %d", len(gaps), text, overdue)
}
func (a *Analysis) orderSizesLine(customers []*Customer) string {
	bins := make([]int, len(a.params.orderBins)+1)
	for _, c := range customers {
		for _, order := range c.orders {
			index := 0
			for _, bound := range a.params.orderBins {
				if order.net >= bound*100 {
					index++
				}
			}
			bins[index]++
		}
	}
	return "  order_sizes " + integers(bins)
}
func (a *Analysis) returnsLine(customers []*Customer) string {
	gross, returned := int64(0), int64(0)
	cancelled := 0
	for _, c := range customers {
		for _, order := range a.customerOrders[c.id] {
			if order.net <= 0 {
				cancelled++
			}
			for _, row := range order.rows {
				if row.amount > 0 {
					gross += row.amount
				} else {
					returned -= row.amount
				}
			}
		}
	}
	return fmt.Sprintf("  returns rate %s returned %s cancelled %d", realText(float64(returned)/float64(gross)), amount(returned), cancelled)
}
func (a *Analysis) rfmLine(members []int) string {
	totals := make([]float64, 3)
	counts := map[string]int{}
	for _, i := range members {
		for part, value := range a.scores[i] {
			totals[part] += float64(value)
		}
		counts[a.codes[i]]++
	}
	mode := ""
	for code, count := range counts {
		if mode == "" || count > counts[mode] || count == counts[mode] && code < mode {
			mode = code
		}
	}
	for f := range totals {
		totals[f] /= float64(len(members))
	}
	return fmt.Sprintf("  rfm r %s f %s m %s mode %s %d", realText(totals[0]), realText(totals[1]), realText(totals[2]), mode, counts[mode])
}
func (a *Analysis) categoriesLine(segment int) string {
	parts := []string{"  categories"}
	for _, category := range a.rankings[segment][:min(len(a.rankings[segment]), a.params.topCategories)] {
		share := float64(a.segmentCategories[segment][category]) / float64(a.segmentSpends[segment])
		lift := share / (float64(a.overallCategories[category]) / float64(a.totalSpend))
		parts = append(parts, category, realText(share), realText(lift))
	}
	return strings.Join(parts, " ")
}
func (a *Analysis) outliersLine(members []int) string {
	outliers := []string{}
	if len(members) >= 2 {
		distances := []float64{}
		for _, i := range members {
			distances = append(distances, a.distances[i])
		}
		limit := mean(distances) + a.params.outlierSD*sampleSD(distances)
		for _, i := range members {
			if a.distances[i] > limit {
				outliers = append(outliers, a.customers[i].id)
			}
		}
	}
	return strings.Join(append([]string{"  outliers", strconv.Itoa(len(outliers))}, outliers...), " ")
}
func (a *Analysis) segmentProfile(segment int) []string {
	members := a.final.solution.members[segment]
	customers := a.segmentCustomers[segment]
	size := len(members)
	center := a.centers[segment]
	spend := a.segmentSpends[segment]
	lines := []string{fmt.Sprintf("segment %d %s rule %d size %d share %s revenue %s revenue_share %s", segment+1, a.names[segment], a.final.ruleNumbers[segment], size, realText(float64(size)/float64(len(a.customers))), amount(spend), realText(float64(spend)/float64(a.totalSpend))), "  center " + reals(center)}
	values := originalScale(center, a.means, a.sds)
	parts := []string{"  value"}
	for f, name := range featureNames {
		parts = append(parts, name, realText(values[f]))
	}
	lines = append(lines, strings.Join(parts, " "), "  traits "+strings.Join(traits(center), " "), a.medianLine(customers), "  related "+a.related(members, a.k-1)+" "+a.related(members, a.k+1))
	top := append([]int(nil), members...)
	sort.SliceStable(top, func(i, j int) bool { return a.customers[top[i]].spend > a.customers[top[j]].spend })
	parts = []string{"  top_customers"}
	for _, i := range top[:min(len(top), a.params.topCustomers)] {
		parts = append(parts, a.customers[i].id, amount(a.customers[i].spend))
	}
	lines = append(lines, strings.Join(parts, " "), a.cadenceLine(customers), a.orderSizesLine(customers), fmt.Sprintf("  sse %s share %s", realText(a.segmentSSE[segment]), realText(a.segmentSSE[segment]/a.final.solution.sse)))
	spends := []int64{}
	for _, c := range customers {
		spends = append(spends, c.spend)
	}
	lines = append(lines, "  gini "+realText(gini(spends)), a.returnsLine(customers))
	silhouettes := []float64{}
	negative := 0
	for _, i := range members {
		silhouettes = append(silhouettes, a.silhouettes[i])
		if a.silhouettes[i] < 0 {
			negative++
		}
	}
	return append(lines, fmt.Sprintf("  silhouette %s negative %d", realText(mean(silhouettes)), negative), a.rfmLine(members), a.categoriesLine(segment), a.outliersLine(members))
}
func (a *Analysis) segmentNumbers() string {
	values := make([]int, a.k)
	for i := range values {
		values[i] = i + 1
	}
	return integers(values)
}
func (a *Analysis) categoryMixLines() []string {
	lines := []string{"category_mix " + a.segmentNumbers()}
	for _, category := range a.categoryNames {
		shares := []float64{}
		for j, totals := range a.segmentCategories {
			shares = append(shares, float64(totals[category])/float64(a.segmentSpends[j]))
		}
		lines = append(lines, category+" "+reals(shares))
	}
	return lines
}
func (a *Analysis) recencyTableLines() []string {
	lines := []string{"rfm_recency " + a.segmentNumbers()}
	for score := 5; score >= 1; score-- {
		counts := make([]int, a.k)
		for i, scores := range a.scores {
			if scores[0] == score {
				counts[a.labels[i]]++
			}
		}
		lines = append(lines, fmt.Sprintf("r=%d %s", score, integers(counts)))
	}
	return append(lines, "ari rfm_codes "+realText(adjustedRand(a.codes, a.labels)))
}
func (a *Analysis) centerDistanceLines() []string {
	lines := []string{"center_distances"}
	for j, center := range a.centers {
		distances := []float64{}
		for _, other := range a.centers {
			distances = append(distances, math.Sqrt(squaredDistance(center, other)))
		}
		lines = append(lines, fmt.Sprintf("%d %s", j+1, reals(distances)))
	}
	return lines
}
func (a *Analysis) profilesLines() []string {
	spends := []int64{}
	for _, c := range a.customers {
		spends = append(spends, c.spend)
	}
	blocks := [][]string{{fmt.Sprintf("segments k=%d customers %d revenue %s gini %s", a.k, len(a.customers), amount(a.totalSpend), realText(gini(spends)))}}
	for j := 0; j < a.k; j++ {
		blocks = append(blocks, a.segmentProfile(j))
	}
	return joinBlocks(append(blocks, a.categoryMixLines(), a.recencyTableLines(), a.centerDistanceLines()))
}
func (a *Analysis) subsampleLines() []string {
	lines := []string{fmt.Sprintf("subsamples %d size %d", a.params.subsamples, len(a.customers)*a.params.subsamplePercent/100)}
	for j, values := range a.jaccards {
		smallest := values[0]
		for _, value := range values[1:] {
			smallest = min(smallest, value)
		}
		lines = append(lines, fmt.Sprintf("segment %d %s mean_jaccard %s min_jaccard %s", j+1, a.names[j], realText(mean(values)), realText(smallest)))
	}
	return lines
}
func (a *Analysis) ablationLines() []string {
	lines := []string{"ablation"}
	for f, name := range featureNames {
		points := [][]float64{}
		for _, point := range a.points {
			reduced := append([]float64(nil), point[:f]...)
			reduced = append(reduced, point[f+1:]...)
			points = append(points, reduced)
		}
		seeds := maximin(points, a.k, 1)
		run := newRun("maximin", 1, seeds, points, a.params.maxIterations)
		index := adjustedRand(run.improved.labels, a.labels)
		lines = append(lines, fmt.Sprintf("without %s seeds %s iterations %d converged %s transfers %d sse %s ari %s", name, a.ids(seeds), run.lloyd.iterations, yesNo(run.lloyd.converged), run.improved.transfers, realText(run.improved.sse), realText(index)))
	}
	return lines
}
func (a *Analysis) drilldownLines() []string {
	members := a.final.solution.members[0]
	points := [][]float64{}
	for _, i := range members {
		points = append(points, a.points[i])
	}
	seeds := maximin(points, 2, 1)
	run := newRun("maximin", 1, seeds, points, a.params.maxIterations)
	parts := newSolution(points, run.improved.labels, 2)
	before, after := a.segmentSSE[0], run.improved.sse
	globalSeeds := []int{}
	for _, seed := range seeds {
		globalSeeds = append(globalSeeds, members[seed])
	}
	lines := []string{fmt.Sprintf("drilldown segment 1 %s size %d seeds %s iterations %d converged %s transfers %d", a.names[0], len(members), a.ids(globalSeeds), run.lloyd.iterations, yesNo(run.lloyd.converged), run.improved.transfers), fmt.Sprintf("sse before %s after %s gain %s", realText(before), realText(after), realText(before-after))}
	for j, size := range parts.sizes {
		lines = append(lines, fmt.Sprintf("part %d size %d center %s", j+1, size, reals(parts.centers[j])))
	}
	return lines
}
func (a *Analysis) robustnessLines() []string {
	return joinBlocks([][]string{a.subsampleLines(), a.ablationLines(), a.drilldownLines()})
}
func (a *Analysis) periodLines() []string {
	p := a.params
	lines := []string{fmt.Sprintf("periods %d days %d", p.periods, p.periodDays)}
	for q := 1; q <= p.periods; q++ {
		first, last := p.referenceDay-q*p.periodDays+1, p.referenceDay-(q-1)*p.periodDays
		revenue := make([]int64, a.k)
		active, acquired := make([]int, a.k), make([]int, a.k)
		for i, c := range a.customers {
			label := a.labels[i]
			buying := false
			for _, order := range c.orders {
				if first <= order.day && order.day <= last {
					revenue[label] += order.net
					buying = true
				}
			}
			if buying {
				active[label]++
			}
			day := p.referenceDay - c.tenure
			if first <= day && day <= last {
				acquired[label]++
			}
		}
		parts := []string{fmt.Sprintf("period %d days %d %d revenue", q, first, last)}
		for _, value := range revenue {
			parts = append(parts, amount(value))
		}
		lines = append(lines, strings.Join(parts, " ")+" active "+integers(active)+" acquired "+integers(acquired))
	}
	return lines
}
func (a *Analysis) migrationLines() []string {
	day := a.params.snapshotDay
	snapshot := eligibleCustomers(groupOrders(a.data.validRows, 1, day), day)
	previous := map[string]int{}
	for _, c := range snapshot {
		point := standardize(c.transformed(), a.means, a.sds)
		labels, _ := assign([][]float64{point}, a.centers)
		previous[c.id] = labels[0]
	}
	table := make([][]int, a.k+1)
	for j := range table {
		table[j] = make([]int, a.k)
	}
	moved := []string{}
	stayed, fresh := 0, 0
	for i, c := range a.customers {
		label := a.labels[i]
		origin, exists := previous[c.id]
		if !exists {
			table[a.k][label]++
			fresh++
			continue
		}
		table[origin][label]++
		if origin == label {
			stayed++
		} else {
			moved = append(moved, fmt.Sprintf("%s %d %d", c.id, origin+1, label+1))
		}
	}
	lost := 0
	for id := range previous {
		if _, exists := a.numbers[id]; !exists {
			lost++
		}
	}
	lines := []string{fmt.Sprintf("migration day %d customers %d", day, len(snapshot)), "from\\to " + a.segmentNumbers()}
	for j, counts := range table {
		label := "none"
		if j < a.k {
			label = strconv.Itoa(j + 1)
		}
		lines = append(lines, label+" "+integers(counts))
	}
	lines = append(lines, "moved_customers")
	lines = append(lines, moved...)
	return append(lines, fmt.Sprintf("stayed %d moved %d new %d lost %d", stayed, len(moved), fresh, lost))
}
func (a *Analysis) outcomeLines() []string {
	first, last := a.params.referenceDay+1, a.params.referenceDay+a.params.outcomeDays
	orders := groupOrders(a.data.validRows, first, last)
	purchases := map[string]int64{}
	for _, order := range orders {
		if order.net > 0 {
			purchases[order.customer] += order.net
		}
	}
	lines := []string{fmt.Sprintf("outcome days %d %d", first, last)}
	for j, customers := range a.segmentCustomers {
		buyers := 0
		spend := int64(0)
		for _, c := range customers {
			if value, exists := purchases[c.id]; exists {
				buyers++
				spend += value
			}
		}
		lines = append(lines, fmt.Sprintf("segment %d %s size %d buyers %d rate %s revenue %s per_customer %s", j+1, a.names[j], len(customers), buyers, realText(float64(buyers)/float64(len(customers))), amount(spend), realText((float64(spend)/100)/float64(len(customers)))))
	}
	outside := 0
	spend := int64(0)
	for id, value := range purchases {
		if _, exists := a.numbers[id]; !exists {
			outside++
			spend += value
		}
	}
	return append(lines, fmt.Sprintf("unsegmented buyers %d revenue %s", outside, amount(spend)))
}
func (a *Analysis) trackingLines() []string {
	return joinBlocks([][]string{a.periodLines(), a.migrationLines(), a.outcomeLines()})
}
func (a *Analysis) dataLines() []string {
	used, returns, later, valid := 0, 0, 0, 0
	for _, row := range a.data.validRows {
		if row.day <= a.params.referenceDay {
			used++
			if row.amount < 0 {
				returns++
			}
		} else {
			later++
		}
	}
	for _, order := range a.referenceOrders {
		if order.net > 0 {
			valid++
		}
	}
	excluded := []string{}
	for id := range a.data.customers {
		if _, exists := a.numbers[id]; !exists {
			excluded = append(excluded, id)
		}
	}
	sort.Strings(excluded)
	text := "-"
	if len(excluded) > 0 {
		text = strings.Join(excluded, " ")
	}
	return []string{fmt.Sprintf("rows %d duplicates %d zero %d used %d returns %d later %d", a.data.rowCount, a.data.duplicates, a.data.free, used, returns, later), fmt.Sprintf("orders %d valid %d cancelled %d", len(a.referenceOrders), valid, len(a.referenceOrders)-valid), fmt.Sprintf("customers %d clustered %d excluded %d", len(a.data.customers), len(a.customers), len(excluded)), "excluded_ids " + text}
}
func (a *Analysis) categoryLines() []string {
	lines := []string{}
	for _, category := range a.categoryNames {
		total := a.overallCategories[category]
		buyers := 0
		for _, c := range a.customers {
			if c.categorySpend[category] > 0 {
				buyers++
			}
		}
		lines = append(lines, fmt.Sprintf("category %s revenue %s share %s customers %d", category, amount(total), realText(float64(total)/float64(a.totalSpend)), buyers))
	}
	return lines
}
func (a *Analysis) featureSummaryLines() []string {
	lines := []string{}
	for f, name := range featureNames {
		column := []float64{}
		for _, c := range a.customers {
			column = append(column, c.values()[f])
		}
		transform := "none"
		if sqrtFeatures[f] {
			transform = "sqrt"
		}
		lines = append(lines, fmt.Sprintf("feature %s transform %s raw_mean %s raw_sd %s mean %s sd %s", name, transform, realText(mean(column)), realText(sampleSD(column)), realText(a.means[f]), realText(a.sds[f])))
	}
	return lines
}
func (a *Analysis) correlationLines() []string {
	lines := []string{"correlation " + strings.Join(featureNames, " ")}
	for first, name := range featureNames {
		values := []float64{}
		for second := range featureNames {
			values = append(values, correlation(a.points, first, second))
		}
		lines = append(lines, name+" "+reals(values))
	}
	return lines
}
func (a *Analysis) summaryLines() []string {
	return joinBlocks([][]string{a.dataLines(), a.categoryLines(), a.featureSummaryLines(), a.correlationLines()})
}
func main() {
	analysis := newAnalysis(readParams(), readTransactions(), readRules())
	analysis.analyze()
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	files := []struct {
		name  string
		lines []string
	}{{"features.csv", analysis.featuresLines()}, {"runs.txt", analysis.runsLines()}, {"selection.txt", analysis.selectionLines()}, {"segments.csv", analysis.segmentsLines()}, {"profiles.txt", analysis.profilesLines()}, {"robustness.txt", analysis.robustnessLines()}, {"tracking.txt", analysis.trackingLines()}, {"summary.txt", analysis.summaryLines()}}
	for _, file := range files {
		writeLines(file.name, file.lines)
	}
}
