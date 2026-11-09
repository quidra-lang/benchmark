package main

import (
	"fmt"
	"math"
	"os"
	"sort"
	"strconv"
	"strings"
)

func realText(value float64) string {
	text := fmt.Sprintf("%.4f", value)
	if text == "-0.0000" {
		return "0.0000"
	}
	return text
}
func optionalText(value *float64) string {
	if value == nil {
		return "-"
	}
	return realText(*value)
}
func realPointer(value float64) *float64 { return &value }
func reals(values []float64) string {
	fields := []string{}
	for _, value := range values {
		fields = append(fields, realText(value))
	}
	return strings.Join(fields, " ")
}
func integers(values []int) string {
	fields := []string{}
	for _, value := range values {
		fields = append(fields, strconv.Itoa(value))
	}
	return strings.Join(fields, " ")
}
func fourDigit(value float64) float64 {
	if math.Abs(value) >= 1e12 {
		return value
	}
	return math.Round(value*10000) / 10000
}
func ariText(value Fraction) string {
	return fmt.Sprintf("%d/%d %s", value.P, value.Q, realText(value.Value()))
}
func pairValues(matrix [][]float64) []float64 {
	values := []float64{}
	for i := range matrix {
		for j := i + 1; j < len(matrix); j++ {
			values = append(values, matrix[i][j])
		}
	}
	return values
}
func histogramBin(value, maximum float64) int { return min(9, int(math.Floor(10*value/maximum))) }
func maxInt(values []int) int {
	best := values[0]
	for _, value := range values[1:] {
		best = max(best, value)
	}
	return best
}
func maxReal(values []float64) float64 {
	best := values[0]
	for _, value := range values[1:] {
		best = max(best, value)
	}
	return best
}
func minReal(values []float64) float64 {
	best := values[0]
	for _, value := range values[1:] {
		best = min(best, value)
	}
	return best
}
func centroid(vectors [][]float64) []float64 {
	center := make([]float64, len(vectors[0]))
	for f := range center {
		total := 0.0
		for _, vector := range vectors {
			total += vector[f]
		}
		center[f] = total / float64(len(vectors))
	}
	return center
}
func clusterMembers(partition []int, groups int) [][]int {
	members := make([][]int, groups)
	for i, number := range partition {
		members[number-1] = append(members[number-1], i)
	}
	return members
}
func majorityClass(row []int) int {
	best := 0
	for t := 1; t < len(row); t++ {
		if row[t] > row[best] {
			best = t
		}
	}
	return best
}
func connectedComponents(count int, edges []Edge) []int {
	component := make([]int, count)
	for i := range component {
		component[i] = i
	}
	for _, edge := range edges {
		old, current := component[edge.Child], component[edge.Parent]
		for u := range component {
			if component[u] == old {
				component[u] = current
			}
		}
	}
	return component
}
func joinParts(parts [][]string) []string {
	lines := []string{}
	for i, part := range parts {
		if i > 0 {
			lines = append(lines, "")
		}
		lines = append(lines, part...)
	}
	return lines
}
func rowSelection(vectors [][]float64, indices []int) [][]float64 {
	rows := make([][]float64, len(indices))
	for i, index := range indices {
		rows[i] = vectors[index]
	}
	return rows
}
func rankedIndices(values []float64, descending, rounded bool) []int {
	order := make([]int, len(values))
	for i := range order {
		order[i] = i
	}
	sort.Slice(order, func(i, j int) bool {
		a, b := values[order[i]], values[order[j]]
		if rounded {
			a, b = fourDigit(a), fourDigit(b)
		}
		if a == b {
			return order[i] < order[j]
		}
		if descending {
			return a > b
		}
		return a < b
	})
	return order
}

type Settings struct {
	InconsistencyDepthText                                           string
	Distance, Standardize                                            string
	Linkages                                                         []string
	CutHeights                                                       []float64
	CutCounts                                                        []int
	InconsistencyDepth, InconsistencyCount, GapMaxK, ListSize, Width int
	CompareLinkage                                                   string
	Replicates, Percent                                              int
	Seed                                                             int64
	RefineIterations                                                 int
}

func newSettings(entries map[string][]string) Settings {
	depth := 0
	for _, digit := range entries["INCONSISTENCY"][0] {
		depth = min(120, depth*10+int(digit-'0'))
	}
	settings := Settings{Distance: entries["DISTANCE"][0], Standardize: entries["STANDARDIZE"][0], Linkages: entries["LINKAGES"], InconsistencyDepth: depth, InconsistencyDepthText: entries["INCONSISTENCY"][0], InconsistencyCount: integer(entries["INCONSISTENCY"][1]), GapMaxK: integer(entries["GAP_MAX_K"][0]), ListSize: integer(entries["LIST_SIZE"][0]), Width: integer(entries["DENDROGRAM_WIDTH"][0]), CompareLinkage: entries["COMPARE_LINKAGE"][0], Replicates: integer(entries["SUBSAMPLES"][0]), Percent: integer(entries["SUBSAMPLES"][1]), Seed: int64(integer(entries["SUBSAMPLES"][2])), RefineIterations: integer(entries["REFINE_ITERATIONS"][0])}
	for _, value := range entries["CUT_HEIGHTS"] {
		settings.CutHeights = append(settings.CutHeights, number(value))
	}
	for _, value := range entries["CUT_K"] {
		settings.CutCounts = append(settings.CutCounts, integer(value))
	}
	return settings
}

type Minstd struct{ State int64 }

func (g *Minstd) Draw() int64 { g.State = 48271 * g.State % 2147483647; return g.State }

type Tree struct {
	Merges         []Merge
	Count          int
	Heights        []float64
	Children       [][2]int
	Order          []int
	Members        [][]int
	Depths         []int
	SubtreeHeights []float64
}

func newTree(merges []Merge, count int) *Tree {
	tree := &Tree{Merges: merges, Count: count, Children: orderedChildren(merges, count), Members: make([][]int, count), Depths: make([]int, count)}
	tree.Order = leafOrder(tree.Children, count)
	for u := 0; u < count; u++ {
		tree.Members[u] = []int{u}
	}
	for _, merge := range merges {
		tree.Heights = append(tree.Heights, merge.Height)
		members := append([]int(nil), tree.Members[merge.A]...)
		members = append(members, tree.Members[merge.B]...)
		tree.Members = append(tree.Members, members)
		tree.Depths = append(tree.Depths, 1+max(tree.Depths[merge.A], tree.Depths[merge.B]))
		tree.SubtreeHeights = append(tree.SubtreeHeights, max(merge.Height, tree.SubtreeHeight(merge.A), tree.SubtreeHeight(merge.B)))
	}
	return tree
}
func (t *Tree) Root() int { return 2*t.Count - 2 }
func (t *Tree) HeightOf(node int) float64 {
	if node < t.Count {
		return 0
	}
	return t.Heights[node-t.Count]
}
func (t *Tree) SubtreeHeight(node int) float64 {
	if node < t.Count {
		return 0
	}
	return t.SubtreeHeights[node-t.Count]
}
func (t *Tree) Partition(selected []bool) []int {
	owner := make([]int, t.Count)
	for i := range owner {
		owner[i] = i
	}
	for step, chosen := range selected {
		if chosen {
			node := t.Count + step
			for _, u := range t.Members[node] {
				owner[u] = node
			}
		}
	}
	numbers := make([]int, 2*t.Count-1)
	groups := 0
	for _, u := range t.Order {
		if numbers[owner[u]] == 0 {
			groups++
			numbers[owner[u]] = groups
		}
	}
	result := make([]int, t.Count)
	for u := range result {
		result[u] = numbers[owner[u]]
	}
	return result
}
func (t *Tree) CutAtHeight(height float64) []int {
	selected := make([]bool, len(t.Merges))
	for i, value := range t.SubtreeHeights {
		selected[i] = value <= height
	}
	return t.Partition(selected)
}
func (t *Tree) CutInto(k int) []int {
	selected := make([]bool, len(t.Merges))
	for step := range selected {
		selected[step] = step < t.Count-k
	}
	return t.Partition(selected)
}
func (t *Tree) Cophenetic() [][]float64 {
	matrix := floatMatrix(t.Count, t.Count)
	for _, merge := range t.Merges {
		for _, i := range t.Members[merge.A] {
			for _, j := range t.Members[merge.B] {
				matrix[i][j], matrix[j][i] = merge.Height, merge.Height
			}
		}
	}
	return matrix
}
func (t *Tree) JoiningHeights() []float64 {
	heights := make([]float64, t.Count)
	for _, merge := range t.Merges {
		for _, child := range []int{merge.A, merge.B} {
			if child < t.Count {
				heights[child] = merge.Height
			}
		}
	}
	return heights
}
func (t *Tree) HeightSequence(step, depth int) []float64 {
	if depth == 0 {
		return []float64{}
	}
	merge := t.Merges[step]
	sequence := []float64{merge.Height}
	for _, child := range []int{merge.A, merge.B} {
		if child >= t.Count {
			sequence = append(sequence, t.HeightSequence(child-t.Count, depth-1)...)
		}
	}
	return sequence
}
func (t *Tree) Newick(node int, idents []string) string {
	if node < t.Count {
		return idents[node]
	}
	branches := []string{}
	for _, child := range t.Children[node-t.Count] {
		branches = append(branches, t.Newick(child, idents)+":"+realText(t.HeightOf(node)-t.HeightOf(child)))
	}
	return "(" + strings.Join(branches, ",") + ")"
}

type Evaluation struct {
	Partition, Sizes []int
	Silhouette, Dunn *float64
	WSS              float64
	CH               *float64
	ARI              Fraction
}

func (e Evaluation) Text() string {
	return fmt.Sprintf("sizes %s silhouette %s dunn %s wss %s ch %s ari %s", integers(e.Sizes), optionalText(e.Silhouette), optionalText(e.Dunn), realText(e.WSS), optionalText(e.CH), ariText(e.ARI))
}

type LinkageResult struct {
	Method                string
	Tree                  *Tree
	Cophenetic            []float64
	Correlation           float64
	HeightCuts, CountCuts []Evaluation
	LabelPartition        []int
}
type Study struct {
	FeatureNames                     []string
	Settings                         Settings
	Count                            int
	Idents, Labels, Classes          []string
	Targets                          []int
	Raw, Vectors, Distances          [][]float64
	Means, Deviations, DistancePairs []float64
	DistanceMax                      float64
	Neighbors                        []int
	Results                          []*LinkageResult
	Chosen                           *LinkageResult
	Kappa                            int
	SelectedCut                      Evaluation
	Selected                         []int
	Members                          [][]int
	Silhouettes                      []float64
	Table                            [][]int
	Majority                         []int
}

func newStudy(names []string, observations []Observation, settings Settings) *Study {
	study := &Study{FeatureNames: names, Settings: settings, Count: len(observations)}
	labels := map[string]bool{}
	for _, observation := range observations {
		study.Idents = append(study.Idents, observation.Ident)
		study.Labels = append(study.Labels, observation.Label)
		study.Raw = append(study.Raw, observation.Values)
		labels[observation.Label] = true
	}
	for label := range labels {
		study.Classes = append(study.Classes, label)
	}
	sort.Strings(study.Classes)
	for _, label := range study.Labels {
		study.Targets = append(study.Targets, sort.SearchStrings(study.Classes, label))
	}
	study.Means, study.Deviations = featureStatistics(study.Raw)
	study.Vectors = study.Raw
	if settings.Standardize == "yes" {
		study.Vectors = standardize(study.Raw, study.Means, study.Deviations)
	}
	study.Distances = distanceMatrix(study.Vectors, settings.Distance)
	study.DistancePairs = pairValues(study.Distances)
	study.DistanceMax = maxReal(study.DistancePairs)
	for i := 0; i < study.Count; i++ {
		best := -1
		for j := 0; j < study.Count; j++ {
			if j != i && (best < 0 || study.Distances[i][j] < study.Distances[i][best]) {
				best = j
			}
		}
		study.Neighbors = append(study.Neighbors, best)
	}
	for _, method := range settings.Linkages {
		study.Results = append(study.Results, study.AnalyseLinkage(method))
	}
	chosen, position := study.Results[0], 0
	for _, result := range study.Results {
		for i, cut := range result.CountCuts {
			if cut.ARI.Greater(chosen.CountCuts[position].ARI) {
				chosen, position = result, i
			}
		}
	}
	study.Chosen = chosen
	study.Kappa = settings.CutCounts[position]
	study.SelectedCut = chosen.CountCuts[position]
	study.Selected = study.SelectedCut.Partition
	study.Members = clusterMembers(study.Selected, study.Kappa)
	study.Silhouettes = silhouetteValues(study.Selected, study.Kappa, study.Distances)
	study.Table = study.ClassTable(study.Selected)
	for _, row := range study.Table {
		study.Majority = append(study.Majority, majorityClass(row))
	}
	return study
}
func (s *Study) ClassTable(partition []int) [][]int {
	zero := make([]int, len(partition))
	for i, value := range partition {
		zero[i] = value - 1
	}
	return contingencyTable(zero, s.Targets, maxInt(partition), len(s.Classes))
}
func (s *Study) LabelARI(partition []int) Fraction { return adjustedRandIndex(s.ClassTable(partition)) }
func (s *Study) MatchCount(partition []int) int {
	total := 0
	for _, row := range s.ClassTable(partition) {
		total += maxInt(row)
	}
	return total
}
func meanSilhouette(partition []int, delta [][]float64) *float64 {
	groups := maxInt(partition)
	if groups < 2 {
		return nil
	}
	return realPointer(sequentialSum(silhouetteValues(partition, groups, delta)) / float64(len(partition)))
}
func (s *Study) Centroids(partition []int) [][]float64 {
	centers := [][]float64{}
	for _, group := range clusterMembers(partition, maxInt(partition)) {
		centers = append(centers, centroid(rowSelection(s.Vectors, group)))
	}
	return centers
}
func (s *Study) WithinSum(partition []int) float64 {
	centers := s.Centroids(partition)
	total := 0.0
	for i, number := range partition {
		total += squaredDistance(s.Vectors[i], centers[number-1])
	}
	return total
}
func (s *Study) DunnIndex(partition []int, groups int) *float64 {
	diameter, separation := 0.0, math.Inf(1)
	for i := 0; i < s.Count; i++ {
		for j := i + 1; j < s.Count; j++ {
			value := s.Distances[i][j]
			if partition[i] == partition[j] {
				diameter = max(diameter, value)
			} else {
				separation = min(separation, value)
			}
		}
	}
	if groups >= 2 && diameter > 0 {
		return realPointer(separation / diameter)
	}
	return nil
}
func (s *Study) Evaluate(partition []int) Evaluation {
	groups := maxInt(partition)
	members := clusterMembers(partition, groups)
	sizes := []int{}
	for _, group := range members {
		sizes = append(sizes, len(group))
	}
	wss := s.WithinSum(partition)
	var ch *float64
	if groups >= 2 && groups < s.Count {
		overall := centroid(s.Vectors)
		centers := s.Centroids(partition)
		bss := 0.0
		for g, size := range sizes {
			bss += float64(size) * squaredDistance(centers[g], overall)
		}
		ch = realPointer((bss / float64(groups-1)) / (wss / float64(s.Count-groups)))
	}
	return Evaluation{partition, sizes, meanSilhouette(partition, s.Distances), s.DunnIndex(partition, groups), wss, ch, s.LabelARI(partition)}
}
func (s *Study) AnalyseLinkage(method string) *LinkageResult {
	tree := newTree(agglomerate(s.Distances, method), s.Count)
	coph := pairValues(tree.Cophenetic())
	result := &LinkageResult{Method: method, Tree: tree, Cophenetic: coph, Correlation: correlation(s.DistancePairs, coph), LabelPartition: tree.CutInto(len(s.Classes))}
	for _, height := range s.Settings.CutHeights {
		result.HeightCuts = append(result.HeightCuts, s.Evaluate(tree.CutAtHeight(height)))
	}
	for _, k := range s.Settings.CutCounts {
		result.CountCuts = append(result.CountCuts, s.Evaluate(tree.CutInto(k)))
	}
	return result
}
func (s *Study) LinkageTable() []string {
	lines := []string{"method,step,a,b,height,size"}
	for _, result := range s.Results {
		for step, merge := range result.Tree.Merges {
			lines = append(lines, fmt.Sprintf("%s,%d,%d,%d,%s,%d", result.Method, step+1, merge.A, merge.B, realText(merge.Height), merge.Size))
		}
	}
	return lines
}
func (s *Study) ClustersTable() []string {
	header := []string{"id", "label"}
	for _, result := range s.Results {
		for j := range s.Settings.CutHeights {
			header = append(header, fmt.Sprintf("%s_h%d", result.Method, j+1))
		}
		for _, k := range s.Settings.CutCounts {
			header = append(header, fmt.Sprintf("%s_k%d", result.Method, k))
		}
	}
	lines := []string{strings.Join(header, ",")}
	for i := 0; i < s.Count; i++ {
		fields := []string{s.Idents[i], s.Labels[i]}
		for _, result := range s.Results {
			for _, cuts := range [][]Evaluation{result.HeightCuts, result.CountCuts} {
				for _, cut := range cuts {
					fields = append(fields, strconv.Itoa(cut.Partition[i]))
				}
			}
		}
		lines = append(lines, strings.Join(fields, ","))
	}
	return lines
}
func (s *Study) DendrogramReport() []string {
	blocks := [][]string{}
	width := s.Settings.Width
	for _, result := range s.Results {
		tree := result.Tree
		maximum := maxReal(tree.Heights)
		cuts := []int{}
		for _, height := range s.Settings.CutHeights {
			cuts = append(cuts, column(height, maximum, width))
		}
		lines := []string{fmt.Sprintf("dendrogram %s height_max %s width %d", result.Method, realText(maximum), width)}
		lines = append(lines, dendrogramRows(tree.Merges, tree.Children, tree.Order, s.Idents, s.Labels, maximum, cuts, width)...)
		for i, height := range s.Settings.CutHeights {
			text := "-"
			if cuts[i] <= width {
				text = strconv.Itoa(cuts[i])
			}
			lines = append(lines, "cut "+realText(height)+" column "+text)
		}
		blocks = append(blocks, lines)
	}
	return joinParts(blocks)
}
func (s *Study) TreesReport() []string {
	lines := []string{}
	for _, result := range s.Results {
		lines = append(lines, result.Method+" "+result.Tree.Newick(result.Tree.Root(), s.Idents)+";")
	}
	return lines
}
func (s *Study) PairText(i, j int) string {
	return realText(s.Distances[i][j]) + " " + s.Idents[i] + " " + s.Idents[j]
}
func (s *Study) DataPart() []string {
	lines := []string{fmt.Sprintf("data n %d features %d classes %d distance %s standardize %s", s.Count, len(s.FeatureNames), len(s.Classes), s.Settings.Distance, s.Settings.Standardize)}
	for f, name := range s.FeatureNames {
		lines = append(lines, "feature "+name+" mean "+realText(s.Means[f])+" sd "+realText(s.Deviations[f]))
	}
	small, large := [2]int{0, 1}, [2]int{0, 1}
	for i := 0; i < s.Count; i++ {
		for j := i + 1; j < s.Count; j++ {
			if s.Distances[i][j] < s.Distances[small[0]][small[1]] {
				small = [2]int{i, j}
			}
			if s.Distances[i][j] > s.Distances[large[0]][large[1]] {
				large = [2]int{i, j}
			}
		}
	}
	lines = append(lines, fmt.Sprintf("distances pairs %d min %s max %s mean %s", len(s.DistancePairs), s.PairText(small[0], small[1]), s.PairText(large[0], large[1]), realText(sequentialSum(s.DistancePairs)/float64(len(s.DistancePairs)))))
	nearest := 0.0
	reciprocal := 0
	for i, j := range s.Neighbors {
		nearest += s.Distances[i][j]
		if i < j && s.Neighbors[j] == i {
			reciprocal++
		}
	}
	lines = append(lines, fmt.Sprintf("nearest_neighbors mean %s reciprocal_pairs %d", realText(nearest/float64(s.Count)), reciprocal))
	labels := []int{}
	for _, target := range s.Targets {
		labels = append(labels, target+1)
	}
	return append(lines, "labels "+s.Evaluate(labels).Text())
}
func (s *Study) CorrelationPart() []string {
	columns := floatMatrix(len(s.FeatureNames), s.Count)
	for f := range columns {
		for i, row := range s.Raw {
			columns[f][i] = row[f]
		}
	}
	lines := []string{"correlation " + strings.Join(s.FeatureNames, " ")}
	for f, first := range columns {
		values := []float64{}
		for _, second := range columns {
			values = append(values, correlation(first, second))
		}
		lines = append(lines, s.FeatureNames[f]+" "+reals(values))
	}
	return lines
}
func (s *Study) HistogramPart() []string {
	counts := make([]int, 10)
	for _, value := range s.DistancePairs {
		counts[histogramBin(value, s.DistanceMax)]++
	}
	highest := maxInt(counts)
	lines := []string{"histogram"}
	for b, count := range counts {
		line := fmt.Sprintf("%s %s %d", realText(float64(b)*s.DistanceMax/10), realText(float64(b+1)*s.DistanceMax/10), count)
		length := count * 50 / highest
		if length > 0 {
			line += " " + strings.Repeat("#", length)
		}
		lines = append(lines, line)
	}
	return lines
}
func (s *Study) Gaps(tree *Tree) []float64 {
	ordered := append([]float64(nil), tree.SubtreeHeights...)
	sort.Float64s(ordered)
	gaps := []float64{}
	for k := 2; k <= s.Settings.GapMaxK; k++ {
		gaps = append(gaps, ordered[s.Count-k]-ordered[s.Count-k-1])
	}
	return gaps
}
func (s *Study) InconsistencyLine(tree *Tree, step int) string {
	sequence := tree.HeightSequence(step, s.Settings.InconsistencyDepth)
	count := len(sequence)
	mean := sequentialSum(sequence) / float64(count)
	deviation, coefficient := 0.0, 0.0
	if count >= 2 {
		squares := 0.0
		for _, value := range sequence {
			difference := value - mean
			squares += difference * difference
		}
		deviation = math.Sqrt(squares / float64(count-1))
		coefficient = (tree.Heights[step] - mean) / deviation
	}
	return fmt.Sprintf("step %d height %s mean %s sd %s count %d coefficient %s", step+1, realText(tree.Heights[step]), realText(mean), realText(deviation), count, realText(coefficient))
}
func (s *Study) LinkagePart(result *LinkageResult) []string {
	tree := result.Tree
	heights := tree.Heights
	leafPath := 0.0
	for r := 0; r < s.Count-1; r++ {
		leafPath += s.Distances[tree.Order[r]][tree.Order[r+1]]
	}
	inversions := []int{}
	for step := 1; step < len(heights); step++ {
		if heights[step] < heights[step-1] {
			inversions = append(inversions, step)
		}
	}
	lines := []string{"linkage " + result.Method, "cophenetic " + realText(result.Correlation) + " leaf_path " + realText(leafPath), fmt.Sprintf("heights min %s max %s inversions %d", realText(minReal(heights)), realText(maxReal(heights)), len(inversions))}
	for _, step := range inversions {
		lines = append(lines, fmt.Sprintf("inversion step %d height %s previous %s", step+1, realText(heights[step]), realText(heights[step-1])))
	}
	gaps := s.Gaps(tree)
	suggested := 2
	for k := 3; k <= s.Settings.GapMaxK; k++ {
		if fourDigit(gaps[k-2]) > fourDigit(gaps[suggested-2]) {
			suggested = k
		}
	}
	lines = append(lines, "gaps "+reals(gaps), fmt.Sprintf("suggested_k %d", suggested))
	joining := tree.JoiningHeights()
	late := rankedIndices(joining, true, false)[:s.Settings.ListSize]
	texts := []string{}
	for _, i := range late {
		texts = append(texts, s.Idents[i]+":"+realText(joining[i]))
	}
	lines = append(lines, "late_joiners "+strings.Join(texts, " "))
	kinds := make([]int, 3)
	for _, merge := range tree.Merges {
		leaves := 0
		if merge.A < s.Count {
			leaves++
		}
		if merge.B < s.Count {
			leaves++
		}
		kinds[2-leaves]++
	}
	matches := s.MatchCount(result.LabelPartition)
	lines = append(lines, fmt.Sprintf("merges leaf_leaf %d leaf_cluster %d cluster_cluster %d depth %d", kinds[0], kinds[1], kinds[2], tree.Depths[tree.Root()]), fmt.Sprintf("label_cut k %d purity %d/%d %s", len(s.Classes), matches, s.Count, realText(float64(matches)/float64(s.Count))), fmt.Sprintf("inconsistency depth %s", s.Settings.InconsistencyDepthText))
	for step := s.Count - s.Settings.InconsistencyCount - 1; step < s.Count-1; step++ {
		lines = append(lines, s.InconsistencyLine(tree, step))
	}
	for i, height := range s.Settings.CutHeights {
		cut := result.HeightCuts[i]
		lines = append(lines, fmt.Sprintf("cut height %s clusters %d %s", realText(height), len(cut.Sizes), cut.Text()))
	}
	for i, k := range s.Settings.CutCounts {
		lines = append(lines, fmt.Sprintf("cut k %d %s", k, result.CountCuts[i].Text()))
	}
	return lines
}
func (s *Study) ResultOf(method string) *LinkageResult {
	for _, result := range s.Results {
		if result.Method == method {
			return result
		}
	}
	return nil
}
func (s *Study) MSTPart() []string {
	single := s.ResultOf("single")
	edges := minimumSpanningTree(s.Distances)
	total := 0.0
	weights := []float64{}
	linked := make([][]bool, s.Count)
	for i := range linked {
		linked[i] = make([]bool, s.Count)
	}
	for _, edge := range edges {
		total += edge.Weight
		weights = append(weights, edge.Weight)
		linked[edge.Parent][edge.Child], linked[edge.Child][edge.Parent] = true, true
	}
	sort.Float64s(weights)
	heightResult := "match"
	for i, weight := range weights {
		if math.Abs(weight-single.Tree.Heights[i]) > 1e-9 {
			heightResult = "mismatch"
		}
	}
	nnEdges := 0
	for i, j := range s.Neighbors {
		if linked[i][j] {
			nnEdges++
		}
	}
	lines := []string{fmt.Sprintf("mst total %s heights %s nn_edges %d/%d", realText(total), heightResult, nnEdges, s.Count)}
	order := make([]int, len(edges))
	for i := range order {
		order[i] = i
	}
	sort.Slice(order, func(i, j int) bool {
		a, b := edges[order[i]].Weight, edges[order[j]].Weight
		if a == b {
			return order[i] < order[j]
		}
		return a < b
	})
	ordered := []Edge{}
	for _, index := range order {
		ordered = append(ordered, edges[index])
	}
	for position, k := range s.Settings.CutCounts {
		component := connectedComponents(s.Count, ordered[:s.Count-k])
		partition := single.CountCuts[position].Partition
		result := "match"
		for i := 0; i < s.Count; i++ {
			for j := i + 1; j < s.Count; j++ {
				if (component[i] == component[j]) != (partition[i] == partition[j]) {
					result = "mismatch"
				}
			}
		}
		lines = append(lines, fmt.Sprintf("mst partition k %d %s", k, result))
	}
	return lines
}
func (s *Study) ComparePart() []string {
	method := s.Settings.CompareLinkage
	count := len(s.Classes)
	lines := []string{fmt.Sprintf("compare linkage %s k %d", method, count)}
	for _, kind := range distanceTypes {
		delta := distanceMatrix(s.Vectors, kind)
		tree := newTree(agglomerate(delta, method), s.Count)
		coph := correlation(pairValues(delta), pairValues(tree.Cophenetic()))
		partition := tree.CutInto(count)
		lines = append(lines, fmt.Sprintf("metric %s cophenetic %s silhouette %s ari %s", kind, realText(coph), optionalText(meanSilhouette(partition, delta)), ariText(s.LabelARI(partition))))
	}
	return lines
}
func (s *Study) CopheneticPart() []string {
	names := []string{}
	for _, result := range s.Results {
		names = append(names, result.Method)
	}
	lines := []string{"cophenetic_matrix", "linkage " + strings.Join(names, " ")}
	for _, first := range s.Results {
		values := []float64{}
		for _, second := range s.Results {
			values = append(values, correlation(first.Cophenetic, second.Cophenetic))
		}
		lines = append(lines, first.Method+" "+reals(values))
	}
	return lines
}
func partitionARI(first, second []int) Fraction {
	a, b := make([]int, len(first)), make([]int, len(second))
	for i, value := range first {
		a[i] = value - 1
	}
	for i, value := range second {
		b[i] = value - 1
	}
	return adjustedRandIndex(contingencyTable(a, b, maxInt(first), maxInt(second)))
}
func (s *Study) AgreementPart() []string {
	names := []string{}
	for _, result := range s.Results {
		names = append(names, result.Method)
	}
	lines := []string{fmt.Sprintf("agreement k %d", len(s.Classes)), "linkage " + strings.Join(names, " ")}
	for _, first := range s.Results {
		values := []float64{}
		for _, second := range s.Results {
			values = append(values, partitionARI(first.LabelPartition, second.LabelPartition).Value())
		}
		lines = append(lines, first.Method+" "+reals(values))
	}
	return lines
}
func (s *Study) SummaryPart() []string {
	values := []float64{}
	for _, result := range s.Results {
		values = append(values, result.Correlation)
	}
	names := []string{}
	for _, i := range rankedIndices(values, true, true) {
		names = append(names, s.Results[i].Method)
	}
	lines := []string{"summary", "cophenetic_ranking " + strings.Join(names, " ")}
	for position, k := range s.Settings.CutCounts {
		best := s.Results[0]
		for _, result := range s.Results[1:] {
			if result.CountCuts[position].ARI.Greater(best.CountCuts[position].ARI) {
				best = result
			}
		}
		lines = append(lines, fmt.Sprintf("best_ari k %d %s %s", k, best.Method, ariText(best.CountCuts[position].ARI)))
	}
	for _, result := range s.Results {
		best := 0
		for position := 1; position < len(s.Settings.CutCounts); position++ {
			if fourDigit(*result.CountCuts[position].Silhouette) > fourDigit(*result.CountCuts[best].Silhouette) {
				best = position
			}
		}
		lines = append(lines, fmt.Sprintf("best_silhouette %s k %d %s", result.Method, s.Settings.CutCounts[best], optionalText(result.CountCuts[best].Silhouette)))
	}
	return append(lines, fmt.Sprintf("selected %s k %d", s.Chosen.Method, s.Kappa))
}
func (s *Study) ValidationReport() []string {
	parts := [][]string{s.DataPart(), s.CorrelationPart(), s.HistogramPart()}
	for _, result := range s.Results {
		parts = append(parts, s.LinkagePart(result))
	}
	if s.ResultOf("single") != nil {
		parts = append(parts, s.MSTPart())
	}
	parts = append(parts, s.ComparePart(), s.CopheneticPart(), s.AgreementPart(), s.SummaryPart())
	return joinParts(parts)
}
func (s *Study) Separation(first, second []int) float64 {
	best := math.Inf(1)
	for _, i := range first {
		for _, j := range second {
			best = min(best, s.Distances[i][j])
		}
	}
	return best
}
func (s *Study) ClusterLines(g int) []string {
	group := s.Members[g]
	size := len(group)
	silhouette := 0.0
	for _, i := range group {
		silhouette += s.Silhouettes[i]
	}
	silhouette /= float64(size)
	majority := s.Majority[g]
	majorityCount := s.Table[g][majority]
	means := []float64{}
	for f := range s.FeatureNames {
		total := 0.0
		for _, i := range group {
			total += s.Raw[i][f]
		}
		means = append(means, total/float64(size))
	}
	medoid := -1
	medoidSum := 0.0
	for _, i := range group {
		total := 0.0
		for _, j := range group {
			total += s.Distances[i][j]
		}
		if medoid < 0 || total < medoidSum {
			medoid, medoidSum = i, total
		}
	}
	diameter := "0.0000 - -"
	widest := [2]int{-1, -1}
	for position, i := range group {
		for _, j := range group[position+1:] {
			if widest[0] < 0 || s.Distances[i][j] > s.Distances[widest[0]][widest[1]] {
				widest = [2]int{i, j}
			}
		}
	}
	if widest[0] >= 0 {
		diameter = s.PairText(widest[0], widest[1])
	}
	nearest := -1
	separation := 0.0
	for h := 0; h < s.Kappa; h++ {
		if h != g {
			value := s.Separation(group, s.Members[h])
			if nearest < 0 || value < separation {
				nearest, separation = h, value
			}
		}
	}
	return []string{fmt.Sprintf("cluster %d size %d silhouette %s majority %s purity %d/%d %s", g+1, size, realText(silhouette), s.Classes[majority], majorityCount, size, realText(float64(majorityCount)/float64(size))), "  mean " + reals(means), fmt.Sprintf("  medoid %s diameter %s nearest %d separation %s", s.Idents[medoid], diameter, nearest+1, realText(separation))}
}
func (s *Study) SelectionPart() []string {
	lines := []string{fmt.Sprintf("selected linkage %s k %d ari %s silhouette %s", s.Chosen.Method, s.Kappa, ariText(s.SelectedCut.ARI), optionalText(s.SelectedCut.Silhouette))}
	for g := 0; g < s.Kappa; g++ {
		lines = append(lines, s.ClusterLines(g)...)
	}
	return lines
}
func (s *Study) CentroidPart() []string {
	centers := s.Centroids(s.Selected)
	lines := []string{"centroid_distances"}
	for g, first := range centers {
		values := []float64{}
		for _, second := range centers {
			values = append(values, math.Sqrt(squaredDistance(first, second)))
		}
		lines = append(lines, strconv.Itoa(g+1)+" "+reals(values))
	}
	return lines
}
func (s *Study) ProfilePart() []string {
	nameWidth := 0
	for _, name := range s.FeatureNames {
		nameWidth = max(nameWidth, len(name))
	}
	lines := []string{"profile_bars"}
	for g, group := range s.Members {
		lines = append(lines, fmt.Sprintf("cluster %d", g+1))
		for f, name := range s.FeatureNames {
			total := 0.0
			for _, i := range group {
				total += (s.Raw[i][f] - s.Means[f]) / s.Deviations[f]
			}
			zeta := total / float64(len(group))
			length := min(10, int(math.Floor(math.Abs(zeta)*4)))
			bar := strings.Repeat("#", length)
			left, right := strings.Repeat(" ", 10), strings.Repeat(" ", 10)
			if zeta < 0 {
				left = strings.Repeat(" ", 10-length) + bar
			} else {
				right = bar + strings.Repeat(" ", 10-length)
			}
			lines = append(lines, fmt.Sprintf("%-*s %s|%s %s", nameWidth, name, left, right, realText(zeta)))
		}
	}
	return lines
}
func (s *Study) ContingencyPart() []string {
	lines := []string{"contingency", "cluster " + strings.Join(s.Classes, " ") + " total"}
	totals := make([]int, len(s.Classes))
	for g, row := range s.Table {
		total := 0
		for t, value := range row {
			total += value
			totals[t] += value
		}
		lines = append(lines, fmt.Sprintf("%d %s %d", g+1, integers(row), total))
	}
	matches := s.MatchCount(s.Selected)
	return append(lines, fmt.Sprintf("total %s %d", integers(totals), s.Count), fmt.Sprintf("purity %d/%d %s", matches, s.Count, realText(float64(matches)/float64(s.Count))))
}
func (s *Study) MisplacedPart() []string {
	lines := []string{"misplaced"}
	count := 0
	for i, number := range s.Selected {
		majority := s.Majority[number-1]
		if s.Targets[i] != majority {
			count++
			lines = append(lines, fmt.Sprintf("%s label %s cluster %d majority %s", s.Idents[i], s.Labels[i], number, s.Classes[majority]))
		}
	}
	return append(lines, fmt.Sprintf("count %d", count))
}
func (s *Study) WeakestPart() []string {
	lines := []string{"weakest"}
	for _, i := range rankedIndices(s.Silhouettes, false, false)[:s.Settings.ListSize] {
		lines = append(lines, fmt.Sprintf("%s label %s cluster %d silhouette %s", s.Idents[i], s.Labels[i], s.Selected[i], realText(s.Silhouettes[i])))
	}
	return lines
}
func (s *Study) FeaturePart() []string {
	ratios := []float64{}
	for f := range s.FeatureNames {
		values := []float64{}
		for _, vector := range s.Vectors {
			values = append(values, vector[f])
		}
		overall := sequentialSum(values) / float64(s.Count)
		means := []float64{}
		for _, group := range s.Members {
			total := 0.0
			for _, i := range group {
				total += values[i]
			}
			means = append(means, total/float64(len(group)))
		}
		between := 0.0
		for g, group := range s.Members {
			difference := means[g] - overall
			between += float64(len(group)) * difference * difference
		}
		within := 0.0
		for i, number := range s.Selected {
			difference := values[i] - means[number-1]
			within += difference * difference
		}
		ratios = append(ratios, (between/float64(s.Kappa-1))/(within/float64(s.Count-s.Kappa)))
	}
	lines := []string{"features"}
	for rank, f := range rankedIndices(ratios, true, true) {
		lines = append(lines, fmt.Sprintf("%d %s f_ratio %s", rank+1, s.FeatureNames[f], realText(ratios[f])))
	}
	return lines
}
func (s *Study) ClassCounts(tree *Tree, node int) string {
	counts := make([]int, len(s.Classes))
	for _, i := range tree.Members[node] {
		counts[s.Targets[i]]++
	}
	return strings.ReplaceAll(integers(counts), " ", "/")
}
func (s *Study) TopMergesPart() []string {
	tree := s.Chosen.Tree
	lines := []string{"top_merges"}
	for step := s.Count - s.Settings.InconsistencyCount - 1; step < s.Count-1; step++ {
		merge := tree.Merges[step]
		lines = append(lines, fmt.Sprintf("step %d height %s a %d %d %s b %d %d %s", step+1, realText(merge.Height), merge.A, len(tree.Members[merge.A]), s.ClassCounts(tree, merge.A), merge.B, len(tree.Members[merge.B]), s.ClassCounts(tree, merge.B)))
	}
	return lines
}
func (s *Study) DropFeaturePart() []string {
	lines := []string{"drop_feature"}
	for f, name := range s.FeatureNames {
		reduced := make([][]float64, s.Count)
		for i, vector := range s.Vectors {
			for j, value := range vector {
				if j != f {
					reduced[i] = append(reduced[i], value)
				}
			}
		}
		partition := newTree(agglomerate(distanceMatrix(reduced, s.Settings.Distance), s.Chosen.Method), s.Count).CutInto(s.Kappa)
		lines = append(lines, name+" ari_selected "+ariText(partitionARI(partition, s.Selected))+" ari_labels "+ariText(s.LabelARI(partition)))
	}
	return lines
}
func nearestCenter(vector []float64, centers [][]float64) int {
	best := 0
	bestValue := squaredDistance(vector, centers[0])
	for g := 1; g < len(centers); g++ {
		value := squaredDistance(vector, centers[g])
		if value < bestValue {
			best, bestValue = g, value
		}
	}
	return best + 1
}
func (s *Study) RefinementPart() []string {
	limit := s.Settings.RefineIterations
	centers := s.Centroids(s.Selected)
	previous := append([]int(nil), s.Selected...)
	iterations := limit
	for t := 1; t <= limit; t++ {
		assignment := make([]int, s.Count)
		same := true
		for i, vector := range s.Vectors {
			assignment[i] = nearestCenter(vector, centers)
			if assignment[i] != previous[i] {
				same = false
			}
		}
		if same {
			iterations = t
			previous = assignment
			break
		}
		for g, group := range clusterMembers(assignment, s.Kappa) {
			if len(group) > 0 {
				centers[g] = centroid(rowSelection(s.Vectors, group))
			}
		}
		previous = assignment
	}
	refined := previous
	changed := 0
	for i, number := range refined {
		if number != s.Selected[i] {
			changed++
		}
	}
	sizes := []int{}
	for _, group := range clusterMembers(refined, s.Kappa) {
		sizes = append(sizes, len(group))
	}
	return []string{fmt.Sprintf("refinement max_iterations %d", limit), fmt.Sprintf("iterations %d changed %d wss %s -> %s", iterations, changed, realText(s.WithinSum(s.Selected)), realText(s.WithinSum(refined))), "sizes " + integers(sizes) + " silhouette " + optionalText(meanSilhouette(refined, s.Distances)), "ari_selected " + ariText(partitionARI(refined, s.Selected)) + " ari_labels " + ariText(s.LabelARI(refined))}
}
func (s *Study) Jaccard(sample, restricted []int) []float64 {
	first, second := []int{}, []int{}
	for _, number := range restricted {
		first = append(first, number-1)
	}
	for _, number := range sample {
		second = append(second, number-1)
	}
	table := contingencyTable(first, second, s.Kappa, maxInt(sample))
	columns := make([]int, len(table[0]))
	for _, row := range table {
		for h, value := range row {
			columns[h] += value
		}
	}
	values := []float64{}
	for _, row := range table {
		size := 0
		for _, value := range row {
			size += value
		}
		best := Fraction{0, 1}
		if size > 0 {
			for h, common := range row {
				candidate := Fraction{int64(common), int64(size + columns[h] - common)}
				if candidate.Greater(best) {
					best = candidate
				}
			}
		}
		values = append(values, best.Value())
	}
	return values
}
func (s *Study) StabilityPart() []string {
	settings := s.Settings
	generator := Minstd{settings.Seed}
	size := s.Count * settings.Percent / 100
	aris := []float64{}
	jaccards := [][]float64{}
	lines := []string{fmt.Sprintf("stability replicates %d percent %d seed %d", settings.Replicates, settings.Percent, settings.Seed)}
	for b := 1; b <= settings.Replicates; b++ {
		array := make([]int, s.Count)
		for i := range array {
			array[i] = i
		}
		for t := 0; t < size; t++ {
			j := t + int(generator.Draw()%int64(s.Count-t))
			array[t], array[j] = array[j], array[t]
		}
		sample := append([]int(nil), array[:size]...)
		sort.Ints(sample)
		delta := floatMatrix(size, size)
		for u, i := range sample {
			for w, j := range sample {
				delta[u][w] = s.Distances[i][j]
			}
		}
		partition := newTree(agglomerate(delta, s.Chosen.Method), size).CutInto(s.Kappa)
		restricted := []int{}
		for _, i := range sample {
			restricted = append(restricted, s.Selected[i])
		}
		ari := partitionARI(partition, restricted)
		jaccard := s.Jaccard(partition, restricted)
		aris = append(aris, ari.Value())
		jaccards = append(jaccards, jaccard)
		lines = append(lines, fmt.Sprintf("replicate %d size %d ari %s jaccard %s", b, size, ariText(ari), reals(jaccard)))
	}
	means := []float64{}
	for g := 0; g < s.Kappa; g++ {
		total := 0.0
		for _, values := range jaccards {
			total += values[g]
		}
		means = append(means, total/float64(settings.Replicates))
	}
	return append(lines, "mean_ari "+realText(sequentialSum(aris)/float64(settings.Replicates)), "mean_jaccard "+reals(means))
}
func (s *Study) DistanceMapPart() []string {
	frame := "+" + strings.Repeat("-", s.Count) + "+"
	lines := []string{"distance_map " + s.Chosen.Method, frame}
	for _, u := range s.Chosen.Tree.Order {
		row := make([]byte, s.Count)
		for w, v := range s.Chosen.Tree.Order {
			row[w] = "@%#*+=-:. "[histogramBin(s.Distances[u][v], s.DistanceMax)]
		}
		lines = append(lines, "|"+string(row)+"|")
	}
	return append(lines, frame)
}
func (s *Study) ProfilesReport() []string {
	return joinParts([][]string{s.SelectionPart(), s.CentroidPart(), s.ProfilePart(), s.ContingencyPart(), s.MisplacedPart(), s.WeakestPart(), s.FeaturePart(), s.TopMergesPart(), s.DropFeaturePart(), s.RefinementPart(), s.StabilityPart(), s.DistanceMapPart()})
}
func main() {
	names, observations := readObservations()
	study := newStudy(names, observations, newSettings(readSettings()))
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	writeLines("linkage.csv", study.LinkageTable())
	writeLines("clusters.csv", study.ClustersTable())
	writeLines("dendrogram.txt", study.DendrogramReport())
	writeLines("trees.txt", study.TreesReport())
	writeLines("validation.txt", study.ValidationReport())
	writeLines("profiles.txt", study.ProfilesReport())
}
