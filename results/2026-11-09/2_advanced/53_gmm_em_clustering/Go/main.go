package main

import (
	"fmt"
	"math"
	"sort"
	"strconv"
	"strings"
)

type Summary struct {
	K, TypePosition, Parameters    int
	Kind                           string
	Run                            EMRun
	Assignments, Sizes             []int
	MaxResponsibilities, Entropies []float64
	Entropy, BIC, AIC, ICL         float64
}

func parameterCount(k int, kind string) int {
	switch kind {
	case "FULL":
		return 6*k - 1
	case "TIED":
		return 3*k + 2
	case "DIAG":
		return 5*k - 1
	default:
		return 4*k - 1
	}
}
func argmax(values []float64) int {
	best := 0
	for i := 1; i < len(values); i++ {
		if values[i] > values[best] {
			best = i
		}
	}
	return best
}
func summarize(run EMRun, kind string, typePosition, n int) *Summary {
	k := len(run.Model)
	s := &Summary{K: k, Kind: kind, TypePosition: typePosition, Parameters: parameterCount(k, kind), Run: run, Sizes: make([]int, k)}
	for _, record := range run.Records {
		assigned := argmax(record.Responsibilities)
		s.Assignments = append(s.Assignments, assigned)
		s.Sizes[assigned]++
		s.MaxResponsibilities = append(s.MaxResponsibilities, record.Responsibilities[assigned])
		entropy := 0.0
		for _, r := range record.Responsibilities {
			if r > 0 {
				entropy -= r * math.Log(r)
			}
		}
		s.Entropies = append(s.Entropies, entropy)
		s.Entropy += entropy
	}
	s.BIC = -2*run.Loglik + float64(s.Parameters)*math.Log(float64(n))
	s.AIC = -2*run.Loglik + 2*float64(s.Parameters)
	s.ICL = s.BIC + 2*s.Entropy
	return s
}
func criterion(s *Summary, name string) float64 {
	if name == "aic" {
		return s.AIC
	}
	if name == "icl" {
		return s.ICL
	}
	return s.BIC
}
func rankModels(models []*Summary, name string) []*Summary {
	out := append([]*Summary{}, models...)
	sort.Slice(out, func(i, j int) bool {
		a, b := out[i], out[j]
		x, y := rounded4(criterion(a, name)), rounded4(criterion(b, name))
		if x != y {
			return x < y
		}
		if a.Parameters != b.Parameters {
			return a.Parameters < b.Parameters
		}
		if a.K != b.K {
			return a.K < b.K
		}
		return a.TypePosition < b.TypePosition
	})
	return out
}
func contingency(a, b []int, rows, columns int) [][]int {
	out := make([][]int, rows)
	for i := range out {
		out[i] = make([]int, columns)
	}
	for i, c := range a {
		out[c][b[i]]++
	}
	return out
}

type Fraction struct{ Numerator, Denominator int64 }

func gcd(a, b int64) int64 {
	if a < 0 {
		a = -a
	}
	if b < 0 {
		b = -b
	}
	for b != 0 {
		a, b = b, a%b
	}
	return a
}
func ari(table [][]int) Fraction {
	columns := make([]int, len(table[0]))
	s, a, b := int64(0), int64(0), int64(0)
	n := 0
	c2 := func(v int) int64 { return int64(v) * int64(v-1) / 2 }
	for _, row := range table {
		total := 0
		for j, v := range row {
			s += c2(v)
			total += v
			columns[j] += v
		}
		a += c2(total)
		n += total
	}
	for _, v := range columns {
		b += c2(v)
	}
	z := c2(n)
	numerator, denominator := 2*(z*s-a*b), z*(a+b)-2*a*b
	if denominator == 0 {
		return Fraction{1, 1}
	}
	if denominator < 0 {
		numerator, denominator = -numerator, -denominator
	}
	d := gcd(numerator, denominator)
	return Fraction{numerator / d, denominator / d}
}
func fractionText(value Fraction) string {
	return fmt.Sprintf("%d/%d %s", value.Numerator, value.Denominator, number(float64(value.Numerator)/float64(value.Denominator)))
}
func distanceMatrix(points []DataPoint) [][]float64 {
	out := make([][]float64, len(points))
	for i := range out {
		out[i] = make([]float64, len(points))
		for j := range points {
			out[i][j] = distance(points[i].Point, points[j].Point)
		}
	}
	return out
}

type PartitionMetrics struct {
	Silhouette, CH, DB float64
	ClusterSilhouette  []float64
}

func partitionMetrics(points []DataPoint, assigned []int, k int, distances [][]float64) PartitionMetrics {
	out := PartitionMetrics{Silhouette: math.NaN(), CH: math.NaN(), DB: math.NaN(), ClusterSilhouette: make([]float64, k)}
	groups := make([][]int, k)
	centers := make([]Point, k)
	overall := Point{}
	for i, point := range points {
		c := assigned[i]
		groups[c] = append(groups[c], i)
		centers[c].X += point.Point.X
		centers[c].Y += point.Point.Y
		overall.X += point.Point.X
		overall.Y += point.Point.Y
	}
	overall.X /= float64(len(points))
	overall.Y /= float64(len(points))
	nonempty := []int{}
	for c, group := range groups {
		out.ClusterSilhouette[c] = math.NaN()
		if len(group) > 0 {
			nonempty = append(nonempty, c)
			centers[c].X /= float64(len(group))
			centers[c].Y /= float64(len(group))
		}
	}
	g := len(nonempty)
	if g < 2 {
		return out
	}
	silhouetteSum := 0.0
	clusterSums := make([]float64, k)
	for i, c := range assigned {
		s := 0.0
		if len(groups[c]) > 1 {
			a := 0.0
			for _, j := range groups[c] {
				if i != j {
					a += distances[i][j]
				}
			}
			a /= float64(len(groups[c]) - 1)
			b := math.Inf(1)
			for _, other := range nonempty {
				if other == c {
					continue
				}
				total := 0.0
				for _, j := range groups[other] {
					total += distances[i][j]
				}
				b = math.Min(b, total/float64(len(groups[other])))
			}
			s = (b - a) / math.Max(a, b)
		}
		silhouetteSum += s
		clusterSums[c] += s
	}
	out.Silhouette = silhouetteSum / float64(len(points))
	between, within := 0.0, 0.0
	scatter := make([]float64, k)
	for _, c := range nonempty {
		out.ClusterSilhouette[c] = clusterSums[c] / float64(len(groups[c]))
		between += float64(len(groups[c])) * distance2(centers[c], overall)
		total := 0.0
		for _, i := range groups[c] {
			total += distance(points[i].Point, centers[c])
		}
		scatter[c] = total / float64(len(groups[c]))
	}
	for i, point := range points {
		within += distance2(point.Point, centers[assigned[i]])
	}
	out.CH = (between / float64(g-1)) / (within / float64(len(points)-g))
	total := 0.0
	for _, c := range nonempty {
		maximum := 0.0
		for _, other := range nonempty {
			if other != c {
				maximum = math.Max(maximum, (scatter[c]+scatter[other])/distance(centers[c], centers[other]))
			}
		}
		total += maximum
	}
	out.DB = total / float64(g)
	return out
}
func matching(table [][]int) ([]int, int) {
	k := len(table)
	best := []int{}
	bestAgreement := -1
	var visit func([]int, []bool)
	visit = func(permutation []int, used []bool) {
		if len(permutation) == k {
			agreement := 0
			for j, a := range permutation {
				agreement += table[a][j]
			}
			if agreement > bestAgreement {
				bestAgreement = agreement
				best = append([]int{}, permutation...)
			}
			return
		}
		for a := 0; a < k; a++ {
			if !used[a] {
				used[a] = true
				visit(append(permutation, a), used)
				used[a] = false
			}
		}
	}
	visit(nil, make([]bool, k))
	return best, bestAgreement
}
func oneBased(values []int) []int {
	out := make([]int, len(values))
	for i, v := range values {
		out[i] = v + 1
	}
	return out
}
func modelsFile(models []*Summary, n int) []string {
	lines := []string{}
	for index, s := range models {
		if index > 0 {
			lines = append(lines, "")
		}
		lines = append(lines, fmt.Sprintf("model K=%d type=%s", s.K, s.Kind), fmt.Sprintf("parameters %d",
			s.Parameters), "loglik "+number(s.Run.Loglik), "bic "+number(s.BIC), "aic "+number(s.AIC),
			"icl "+number(s.ICL), "mean_entropy "+number(s.Entropy/float64(n)), fmt.Sprintf("settled_at %d",
				s.Run.SettledAt), fmt.Sprintf("largest_increase iteration %d value %s", s.Run.LargestIteration,
				number(s.Run.LargestIncrease)), fmt.Sprintf("violations %d", len(s.Run.Violations)),
			"sizes "+integerList(s.Sizes))
		for k, c := range s.Run.Model {
			e := eigenData(c.Cov)
			lines = append(lines, fmt.Sprintf("component %d weight %s mean %s %s cov %s %s %s axes %s %s angle %s",
				k+1, number(c.Weight), number(c.Mean.X), number(c.Mean.Y), number(c.Cov.A), number(c.Cov.B),
				number(c.Cov.C), number(e.Major), number(e.Minor), number(e.Angle)))
		}
	}
	return lines
}
func traceFile(models []*Summary) []string {
	lines := []string{"K,type,iteration,loglik"}
	for _, s := range models {
		for t, v := range s.Run.Trace {
			lines = append(lines, fmt.Sprintf("%d,%s,%d,%s", s.K, s.Kind, t, number(v)))
		}
	}
	return lines
}
func assignmentFile(points []DataPoint, selected *Summary, km KMeans) []string {
	lines := []string{"id,component,max_responsibility,log_density,kmeans_cluster"}
	for i, point := range points {
		lines = append(lines, fmt.Sprintf("%s,%d,%s,%s,%d", point.ID, selected.Assignments[i]+1, number(selected.MaxResponsibilities[i]),
			number(selected.Run.Records[i].LogDensity), km.Assignment[i]+1))
	}
	return lines
}
func rankingLines(models []*Summary) []string {
	bic, aic, icl := rankModels(models, "bic"), rankModels(models, "aic"), rankModels(models, "icl")
	aicRanks, iclRanks := map[*Summary]int{}, map[*Summary]int{}
	for i, s := range aic {
		aicRanks[s] = i + 1
	}
	for i, s := range icl {
		iclRanks[s] = i + 1
	}
	selected := bic[0]
	lines := []string{"ranking by bic", "rank K type parameters loglik bic delta_bic aic aic_rank icl icl_rank"}
	for i, s := range bic {
		delta := float64(rounded4(s.BIC)-rounded4(selected.BIC)) / 10000
		lines = append(lines, fmt.Sprintf("%d %d %s %d %s %s %s %s %d %s %d", i+1, s.K, s.Kind, s.Parameters,
			number(s.Run.Loglik), number(s.BIC), number(delta), number(s.AIC), aicRanks[s], number(s.ICL),
			iclRanks[s]))
	}
	return append(lines, fmt.Sprintf("selected K=%d type=%s", selected.K, selected.Kind), fmt.Sprintf("best_aic K=%d type=%s",
		aic[0].K, aic[0].Kind), fmt.Sprintf("best_icl K=%d type=%s", icl[0].K, icl[0].Kind))
}
func bestTypeLines(models []*Summary, p Params) []string {
	lines := []string{"best K per type"}
	for _, kind := range p.Types {
		subset := []*Summary{}
		for _, s := range models {
			if s.Kind == kind {
				subset = append(subset, s)
			}
		}
		lines = append(lines, fmt.Sprintf("%s bic %d aic %d icl %d", kind, rankModels(subset, "bic")[0].K,
			rankModels(subset, "aic")[0].K, rankModels(subset, "icl")[0].K))
	}
	return lines
}
func comparisonLines(points []DataPoint, s *Summary, km KMeans, previous *Summary, distances [][]float64) []string {
	gmmMetrics, kmMetrics := partitionMetrics(points, s.Assignments, s.K, distances), partitionMetrics(points, km.Assignment, s.K, distances)
	lines := []string{fmt.Sprintf("K=%d type=%s bic %s", s.K, s.Kind, number(s.BIC)), fmt.Sprintf("  kmeans iterations %d inertia %s",
		km.Iterations, number(km.Inertia)), "  ari " + fractionText(ari(contingency(s.Assignments,
		km.Assignment, s.K, s.K))), "  silhouette gmm " + optional(gmmMetrics.Silhouette) + " kmeans " + optional(kmMetrics.Silhouette),
		"  calinski_harabasz gmm " + optional(gmmMetrics.CH) + " kmeans " + optional(kmMetrics.CH),
		"  davies_bouldin gmm " + optional(gmmMetrics.DB) + " kmeans " + optional(kmMetrics.DB)}
	if previous != nil {
		table := contingency(previous.Assignments, s.Assignments, previous.K, s.K)
		parents, shared := []string{}, []int{}
		for b := 0; b < s.K; b++ {
			parent, count := 0, 0
			for a := 0; a < previous.K; a++ {
				if table[a][b] > count {
					parent, count = a+1, table[a][b]
				}
			}
			text := "-"
			if parent > 0 {
				text = strconv.Itoa(parent)
			}
			parents = append(parents, text)
			shared = append(shared, count)
		}
		lines = append(lines, fmt.Sprintf("  parents K=%d %s shared %s", previous.K, strings.Join(parents, " "), integerList(shared)))
	}
	return lines
}
func violationLines(models []*Summary) []string {
	lines := []string{"violations"}
	for _, s := range models {
		for _, t := range s.Run.Violations {
			lines = append(lines, fmt.Sprintf("K=%d type=%s iteration %d previous %s current %s", s.K, s.Kind, t, number(s.Run.Trace[t-1]), number(s.Run.Trace[t])))
		}
	}
	if len(lines) == 1 {
		lines = append(lines, "none")
	}
	return lines
}
func selectedComponentLines(points []DataPoint, s *Summary, p Params, distances [][]float64) []string {
	lines := []string{"selected components"}
	metrics := partitionMetrics(points, s.Assignments, s.K, distances)
	for k, c := range s.Run.Model {
		soft := 0.0
		inside1, inside2 := 0, 0
		observed := make([]int, len(p.GOFEdges)+1)
		for i, point := range points {
			soft += s.Run.Records[i].Responsibilities[k]
			if s.Assignments[i] != k {
				continue
			}
			q := mahalanobis(point.Point, c.Mean, c.Cov)
			if q <= 1 {
				inside1++
			}
			if q <= 4 {
				inside2++
			}
			radius := math.Sqrt(q)
			bin := 0
			for bin < len(p.GOFEdges) && radius >= p.GOFEdges[bin] {
				bin++
			}
			observed[bin]++
		}
		expected := make([]float64, len(observed))
		chi := 0.0
		for bin := range expected {
			lower := 0.0
			if bin > 0 {
				lower = p.GOFEdges[bin-1]
			}
			upperProbability := 0.0
			if bin < len(p.GOFEdges) {
				upper := p.GOFEdges[bin]
				upperProbability = math.Exp(-upper * upper / 2)
			}
			expected[bin] = float64(s.Sizes[k]) * (math.Exp(-lower*lower/2) - upperProbability)
			difference := float64(observed[bin]) - expected[bin]
			chi += difference * difference / expected[bin]
		}
		e := eigenData(c.Cov)
		lines = append(lines, fmt.Sprintf("component %d weight %s size %d soft_size %s mean %s %s", k+1,
			number(c.Weight), s.Sizes[k], number(soft), number(c.Mean.X), number(c.Mean.Y)), fmt.Sprintf("  cov %s %s %s corr %s",
			number(c.Cov.A), number(c.Cov.B), number(c.Cov.C), number(e.Correlation)), fmt.Sprintf("  eigen %s %s direction %s %s angle %s",
			number(e.Leading), number(e.Trailing), number(e.Direction.X), number(e.Direction.Y),
			number(e.Angle)), fmt.Sprintf("  axes_1sigma %s %s axes_2sigma %s %s", number(e.Major),
			number(e.Minor), number(2*e.Major), number(2*e.Minor)), fmt.Sprintf("  inside_1sigma %d inside_2sigma %d area_1sigma %s",
			inside1, inside2, number(e.Area)), "  silhouette "+optional(metrics.ClusterSilhouette[k]),
			"  gof observed "+integerList(observed)+" expected "+numberList(expected)+" chi2 "+number(chi))
	}
	return lines
}
func overlapLines(s *Summary) []string {
	lines := []string{"overlap"}
	for a := 0; a < s.K; a++ {
		for b := a + 1; b < s.K; b++ {
			d, coefficient := bhattacharyya(s.Run.Model[a], s.Run.Model[b])
			shared := 0.0
			for _, record := range s.Run.Records {
				shared += record.Responsibilities[a] * record.Responsibilities[b]
			}
			lines = append(lines, fmt.Sprintf("%d-%d bhattacharyya %s coefficient %s shared %s", a+1, b+1, number(d), number(coefficient), number(shared)))
		}
	}
	if s.K == 1 {
		lines = append(lines, "none")
	}
	return lines
}
func groupedResponsibilities(records []ERecord, groups [][]int) [][]float64 {
	out := make([][]float64, len(records))
	for i, r := range records {
		out[i] = make([]float64, len(groups))
		for c, group := range groups {
			for _, k := range group {
				out[i][c] += r.Responsibilities[k]
			}
		}
	}
	return out
}
func groupEntropy(values [][]float64) float64 {
	total := 0.0
	for _, row := range values {
		entropy := 0.0
		for _, v := range row {
			if v > 0 {
				entropy -= v * math.Log(v)
			}
		}
		total += entropy
	}
	return total
}
func mergeGroups(groups [][]int, a, b int) [][]int {
	out := [][]int{}
	for i, group := range groups {
		if i == b {
			continue
		}
		next := append([]int{}, group...)
		if i == a {
			next = append(next, groups[b]...)
			sort.Ints(next)
		}
		out = append(out, next)
	}
	return out
}
func clusterName(group []int) string {
	fields := []string{}
	for _, k := range group {
		fields = append(fields, strconv.Itoa(k+1))
	}
	return strings.Join(fields, "+")
}
func mergingLines(s *Summary) []string {
	groups := make([][]int, s.K)
	for k := range groups {
		groups[k] = []int{k}
	}
	lines := []string{"merging", "start entropy " + number(groupEntropy(groupedResponsibilities(s.Run.Records, groups)))}
	for step := 1; len(groups) > 1; step++ {
		aBest, bBest := 0, 1
		bestEntropy := 0.0
		var bestGroups [][]int
		for a := 0; a < len(groups); a++ {
			for b := a + 1; b < len(groups); b++ {
				candidate := mergeGroups(groups, a, b)
				entropy := groupEntropy(groupedResponsibilities(s.Run.Records, candidate))
				if bestGroups == nil || rounded4(entropy) < rounded4(bestEntropy) {
					aBest, bBest, bestEntropy, bestGroups = a, b, entropy, candidate
				}
			}
		}
		aName, bName := clusterName(groups[aBest]), clusterName(groups[bBest])
		groups = bestGroups
		values := groupedResponsibilities(s.Run.Records, groups)
		sizes := make([]int, len(groups))
		for _, row := range values {
			sizes[argmax(row)]++
		}
		lines = append(lines, fmt.Sprintf("step %d merge %s %s entropy %s sizes %s", step, aName, bName, number(bestEntropy), integerList(sizes)))
	}
	return lines
}
func kmeansLines(points []DataPoint, s *Summary, km KMeans) []string {
	table := contingency(s.Assignments, km.Assignment, s.K, s.K)
	permutation, agreement := matching(table)
	lines := []string{fmt.Sprintf("kmeans K=%d", s.K), fmt.Sprintf("iterations %d", km.Iterations), "inertia " + number(km.Inertia),
		"sizes " + integerList(km.Sizes)}
	for j, c := range km.Centers {
		lines = append(lines, fmt.Sprintf("center %d %s %s", j+1, number(c.X), number(c.Y)))
	}
	lines = append(lines, "contingency")
	for _, row := range table {
		lines = append(lines, integerList(row))
	}
	lines = append(lines, "ari "+fractionText(ari(table)), "matching "+integerList(oneBased(permutation)),
		fmt.Sprintf("agreement %d/%d %s", agreement, len(points), number(float64(agreement)/float64(len(points)))))
	disagreements := 0
	for i, point := range points {
		if permutation[km.Assignment[i]] != s.Assignments[i] {
			disagreements++
			lines = append(lines, fmt.Sprintf("disagree %s gmm %d kmeans %d max %s", point.ID, s.Assignments[i]+1, km.Assignment[i]+1, number(s.MaxResponsibilities[i])))
		}
	}
	return append(lines, fmt.Sprintf("disagreements %d", disagreements))
}
func refitLines(points []DataPoint, s *Summary, km KMeans, p Params) []string {
	initial := make(Model, s.K)
	for j, center := range km.Centers {
		a, b, c := 0.0, 0.0, 0.0
		for i, point := range points {
			if km.Assignment[i] == j {
				dx, dy := point.Point.X-center.X, point.Point.Y-center.Y
				a += dx * dx
				b += dx * dy
				c += dy * dy
			}
		}
		count := float64(km.Sizes[j])
		initial[j] = Component{count / float64(len(points)), center, Covariance{a/count + p.Epsilon, b / count, c/count + p.Epsilon}}
	}
	refit := summarize(runEM(points, initial, s.Kind, p), s.Kind, s.TypePosition, len(points))
	return []string{fmt.Sprintf("refit_from_kmeans K=%d type=%s", s.K, s.Kind), fmt.Sprintf("loglik %s bic %s settled_at %d",
		number(refit.Run.Loglik), number(refit.BIC), refit.Run.SettledAt), "sizes " + integerList(refit.Sizes),
		"ari_vs_selected " + fractionText(ari(contingency(s.Assignments, refit.Assignments, s.K,
			s.K)))}
}
func crossValidationLines(points []DataPoint, s *Summary, initial Model, p Params) []string {
	lines := []string{fmt.Sprintf("cross_validation K=%d type=%s folds %d", s.K, s.Kind, p.Folds)}
	total := 0.0
	for f := 0; f < p.Folds; f++ {
		training, testing := []DataPoint{}, []DataPoint{}
		for i, point := range points {
			if i%p.Folds == f {
				testing = append(testing, point)
			} else {
				training = append(training, point)
			}
		}
		run := runEM(training, initial, s.Kind, p)
		_, testLoglik := expectation(testing, run.Model)
		testMean := testLoglik / float64(len(testing))
		total += testMean
		lines = append(lines, fmt.Sprintf("fold %d train %d test %d train_loglik %s test_loglik %s", f+1,
			len(training), len(testing), number(run.Loglik/float64(len(training))), number(testMean)))
	}
	return append(lines, "mean_test_loglik "+number(total/float64(p.Folds)))
}
func uncertainLines(points []DataPoint, s *Summary, threshold float64) []string {
	indices := []int{}
	for i, v := range s.MaxResponsibilities {
		if v < threshold {
			indices = append(indices, i)
		}
	}
	sort.Slice(indices, func(i, j int) bool {
		a, b := indices[i], indices[j]
		x, y := rounded4(s.MaxResponsibilities[a]), rounded4(s.MaxResponsibilities[b])
		return x < y || x == y && a < b
	})
	lines := []string{"uncertain threshold " + number(threshold)}
	for _, i := range indices {
		lines = append(lines, fmt.Sprintf("%s component %d max %s responsibilities %s", points[i].ID, s.Assignments[i]+1,
			number(s.MaxResponsibilities[i]), numberList(s.Run.Records[i].Responsibilities)))
	}
	return append(lines, fmt.Sprintf("count %d", len(indices)))
}
func outlierLines(points []DataPoint, s *Summary, threshold float64) []string {
	indices := []int{}
	for i, r := range s.Run.Records {
		if r.LogDensity < threshold {
			indices = append(indices, i)
		}
	}
	sort.Slice(indices, func(i, j int) bool {
		a, b := indices[i], indices[j]
		x, y := rounded4(s.Run.Records[a].LogDensity), rounded4(s.Run.Records[b].LogDensity)
		return x < y || x == y && a < b
	})
	lines := []string{"outliers threshold " + number(threshold)}
	for _, i := range indices {
		c := s.Run.Model[s.Assignments[i]]
		lines = append(lines, fmt.Sprintf("%s component %d log_density %s q %s", points[i].ID, s.Assignments[i]+1,
			number(s.Run.Records[i].LogDensity), number(mahalanobis(points[i].Point, c.Mean, c.Cov))))
	}
	return append(lines, fmt.Sprintf("count %d", len(indices)))
}
func selectionFile(points []DataPoint, models []*Summary, selected *Summary, bestByK map[int]*Summary,
	kmeans map[int]KMeans, initial map[int]Model, p Params, distances [][]float64) []string {
	parts := [][]string{rankingLines(models), bestTypeLines(models, p)}
	var previous *Summary
	for _, k := range p.K {
		s := bestByK[k]
		parts = append(parts, comparisonLines(points, s, kmeans[k], previous, distances))
		previous = s
	}
	parts = append(parts, violationLines(models), selectedComponentLines(points, selected, p, distances),
		overlapLines(selected), mergingLines(selected), kmeansLines(points, selected, kmeans[selected.K]),
		refitLines(points, selected, kmeans[selected.K], p), crossValidationLines(points, selected,
			initial[selected.K], p), uncertainLines(points, selected, p.Uncertain), outlierLines(points,
			selected, p.LowDensity))
	lines := []string{}
	for i, part := range parts {
		if i > 0 {
			lines = append(lines, "")
		}
		lines = append(lines, part...)
	}
	return lines
}
func canvas(width, height int) [][]byte {
	out := make([][]byte, height)
	for i := range out {
		out[i] = []byte(strings.Repeat(" ", width))
	}
	return out
}
func mapCell(point Point, p Params, stepX, stepY float64) (int, int, bool) {
	column, row := int(math.Floor((point.X-p.XMin)/stepX)), int(math.Floor((p.YMax-point.Y)/stepY))
	return column, row, column >= 0 && column < p.Width && row >= 0 && row < p.Height
}
func densityMapFile(points []DataPoint, s *Summary, p Params) []string {
	stepX, stepY := (p.XMax-p.XMin)/float64(p.Width), (p.YMax-p.YMin)/float64(p.Height)
	centers := []DataPoint{}
	for row := 0; row < p.Height; row++ {
		for column := 0; column < p.Width; column++ {
			centers = append(centers, DataPoint{Point: Point{p.XMin + (float64(column)+0.5)*stepX, p.YMax - (float64(row)+0.5)*stepY}})
		}
	}
	records, _ := expectation(centers, s.Run.Model)
	densities := make([]float64, len(records))
	q := make([][]float64, len(records))
	maximum, mass := 0.0, 0.0
	for i, r := range records {
		density := 0.0
		for _, score := range r.Scores {
			density += math.Exp(score)
		}
		densities[i] = density
		maximum = math.Max(maximum, density)
		mass += density
		q[i] = make([]float64, s.K)
		for k, c := range s.Run.Model {
			q[i][k] = mahalanobis(centers[i].Point, c.Mean, c.Cov)
		}
	}
	mass *= stepX
	mass *= stepY
	densityRows, regionRows, uncertaintyRows, pointRows := canvas(p.Width, p.Height), canvas(p.Width,
		p.Height), canvas(p.Width, p.Height), canvas(p.Width, p.Height)
	levelCounts := [10]int{}
	const levels = " .:-=+*#%@"
	for i, r := range records {
		row, column := i/p.Width, i%p.Width
		level := min(9, int(math.Floor(10*densities[i]/maximum)))
		levelCounts[level]++
		densityRows[row][column] = levels[level]
		regionRows[row][column] = byte('1' + argmax(r.Scores))
		if s.K > 1 {
			entropy := 0.0
			for _, v := range r.Responsibilities {
				if v > 0 {
					entropy -= v * math.Log(v)
				}
			}
			uncertaintyLevel := clamp(int(math.Floor(10*entropy/math.Log(float64(s.K)))), 0, 9)
			uncertaintyRows[row][column] = levels[uncertaintyLevel]
		}
		contour := false
		for k := 0; k < s.K && !contour; k++ {
			if q[i][k] > 4 {
				continue
			}
			for _, delta := range [][2]int{{0, -1}, {0, 1}, {-1, 0}, {1, 0}} {
				x, y := column+delta[0], row+delta[1]
				if x >= 0 && x < p.Width && y >= 0 && y < p.Height && q[y*p.Width+x][k] > 4 {
					contour = true
					break
				}
			}
		}
		if contour {
			pointRows[row][column] = '.'
		}
	}
	for k, c := range s.Run.Model {
		column, row, inside := mapCell(c.Mean, p, stepX, stepY)
		if inside {
			densityRows[row][column] = byte('1' + k)
		}
	}
	pointComponents := make([]int, p.Width*p.Height)
	for i := range pointComponents {
		pointComponents[i] = -1
	}
	outside := 0
	for i, point := range points {
		column, row, inside := mapCell(point.Point, p, stepX, stepY)
		if !inside {
			outside++
			continue
		}
		index := row*p.Width + column
		old := pointComponents[index]
		if old == -1 {
			pointComponents[index] = s.Assignments[i]
		} else if old != s.Assignments[i] {
			pointComponents[index] = -2
		}
	}
	for index, c := range pointComponents {
		if c == -1 {
			continue
		}
		row, column := index/p.Width, index%p.Width
		if c == -2 {
			pointRows[row][column] = '*'
		} else {
			pointRows[row][column] = byte('1' + c)
		}
	}
	lines := []string{fmt.Sprintf("density K=%d type=%s", s.K, s.Kind), fmt.Sprintf("x %s %s y %s %s grid %dx%d",
		number(p.XMin), number(p.XMax), number(p.YMin), number(p.YMax), p.Width, p.Height), "max_density " + numberDigits(maximum,
		6) + " mass_in_map " + number(mass)}
	lines = append(lines, framed(densityRows)...)
	for level, count := range levelCounts {
		lines = append(lines, fmt.Sprintf("level %d \"%c\" from %s cells %d", level, levels[level], numberDigits(float64(level)*maximum/10, 6), count))
	}
	lines = append(lines, "", "regions")
	lines = append(lines, framed(regionRows)...)
	lines = append(lines, "", "uncertainty")
	lines = append(lines, framed(uncertaintyRows)...)
	lines = append(lines, "", "points")
	lines = append(lines, framed(pointRows)...)
	return append(lines, fmt.Sprintf("outside %d", outside))
}
func clamp(value, low, high int) int { return min(max(value, low), high) }
func main() {
	points, initial, p := readDataset()
	models := []*Summary{}
	kmeans := map[int]KMeans{}
	bestByK := map[int]*Summary{}
	for _, k := range p.K {
		subset := []*Summary{}
		for typePosition, kind := range p.Types {
			run := runEM(points, initial[k], kind, p)
			summary := summarize(run, kind, typePosition, len(points))
			models = append(models, summary)
			subset = append(subset, summary)
		}
		bestByK[k] = rankModels(subset, "bic")[0]
		centers := []Point{}
		for _, c := range initial[k] {
			centers = append(centers, c.Mean)
		}
		kmeans[k] = runKMeans(points, centers, p.KMeansMax)
	}
	selected := rankModels(models, "bic")[0]
	distances := distanceMatrix(points)
	writeLines("models.txt", modelsFile(models, len(points)))
	writeLines("loglik_trace.csv", traceFile(models))
	writeLines("assignments.csv", assignmentFile(points, selected, kmeans[selected.K]))
	writeLines("selection.txt", selectionFile(points, models, selected, bestByK, kmeans, initial, p, distances))
	writeLines("density_map.txt", densityMapFile(points, selected, p))
}
