package main

import (
	"fmt"
	"math"
	"math/bits"
	"os"
	"sort"
	"strconv"
	"strings"
)

type Settings struct {
	Model                                    string
	Outgroup, Replicates, Seed, Missing, Low int
	Saturation                               float64
	Exhaustive                               []int
	Hypotheses                               [][]string
}
type Move struct {
	Mask, Swap int
	Value      float64
}
type Addition struct{ Taxon, Mask, Score, Ties int }
type Stepwise struct {
	Tree                           Tree
	InitialScore, Score, Evaluated int
	Additions                      []Addition
}
type Search struct {
	Tree      Tree
	Evaluated int
	Moves     []Move
	Value     float64
}
type ExhaustiveTree struct {
	Tree   Tree
	Score  int
	BME    float64
	Newick string
	Splits map[int]bool
}

func integer(s string) int  { v, e := strconv.Atoi(s); must(e); return v }
func real(s string) float64 { v, e := strconv.ParseFloat(s, 64); must(e); return v }
func popcount(mask int) int { return bits.OnesCount(uint(mask)) }
func yes(b bool) string {
	if b {
		return "yes"
	}
	return "no"
}
func readSettings(taxa []Record) Settings {
	index := map[string]int{}
	for i, t := range taxa {
		index[t.Name] = i
	}
	var p Settings
	for _, line := range strings.Split(strings.TrimSpace(readText("input/params.txt")), "\n") {
		a := strings.Fields(line)
		switch a[0] {
		case "model":
			p.Model = a[1]
		case "outgroup":
			p.Outgroup = index[a[1]]
		case "replicates":
			p.Replicates = integer(a[1])
		case "seed":
			p.Seed = integer(a[1])
		case "max_missing_percent":
			p.Missing = integer(a[1])
		case "saturation_distance":
			p.Saturation = real(a[1])
		case "exhaustive_taxa":
			for _, name := range a[1:] {
				p.Exhaustive = append(p.Exhaustive, index[name])
			}
		case "low_sites":
			p.Low = integer(a[1])
		}
	}
	sort.Ints(p.Exhaustive)
	for _, line := range strings.Split(strings.TrimSpace(readText("input/clades.txt")), "\n") {
		p.Hypotheses = append(p.Hypotheses,
			strings.Fields(line))
	}
	return p
}
func checkAlignment(records []Record, missing int) ([]Record, []string) {
	length := len(records[0].Sequence)
	seen := map[string]bool{}
	var taxa []Record
	var errors []string
	for _, r := range records {
		reason := ""
		if seen[r.Name] {
			reason = "duplicate name"
		} else {
			for i, c := range []byte(r.Sequence) {
				if baseSets[c] == 0 {
					reason = fmt.Sprintf("invalid character %c at column %d",
						c, i+1)
					break
				}
			}
			if reason == "" && len(r.Sequence) != length {
				reason = fmt.Sprintf("length mismatch %d",
					len(r.Sequence))
			}
			if reason == "" {
				n := 0
				for _, c := range r.Sequence {
					if c == '-' || c == 'N' {
						n++
					}
				}
				if 100*n > missing*length {
					reason = fmt.Sprintf("too many missing %d",
						n)
				}
			}
		}
		seen[r.Name] = true
		if reason != "" {
			errors = append(errors, fmt.Sprintf("REJECT line %d %s %s",
				r.Line, r.Name, reason))
		} else {
			taxa = append(taxa, r)
		}
	}
	return taxa, errors
}
func stepwise(list []int, taxa []Record, outgroup, length int) Stepwise {
	t := newTree(len(taxa))
	u := t.Next
	t.Next++
	for _, x := range list[:3] {
		t.connect(u, x, 0)
	}
	result := Stepwise{Tree: t, InitialScore: parsimonyScore(t, taxa,
		outgroup, length)}
	for _, x := range list[3:] {
		bestScore := int(^uint(0) >> 1)
		ties, mask := 0, 0
		var best Tree
		for _, b := range branches(t, taxa, outgroup) {
			v := insertion(t, b, x)
			score := parsimonyScore(v, taxa, outgroup,
				length)
			result.Evaluated++
			if score < bestScore {
				bestScore, ties, mask, best = score, 1, b.Mask, v
			} else if score == bestScore {
				ties++
			}
		}
		t = best
		result.Additions = append(result.Additions,
			Addition{x, mask, bestScore, ties})
	}
	result.Tree = t
	result.Score = parsimonyScore(t, taxa, outgroup, length)
	return result
}
func hillClimb(t Tree, taxa []Record, outgroup int, objective func(Tree) float64) Search {
	result := Search{Tree: t.copy(),
		Value: objective(t)}
	for {
		moved := false
		for _, b := range branches(result.Tree, taxa, outgroup) {
			if b.U < len(taxa) || b.V < len(taxa) {
				continue
			}
			for swap := 1; swap <= 2; swap++ {
				candidate := nni(result.Tree,
					b, swap, taxa, outgroup)
				value := objective(candidate)
				result.Evaluated++
				if value < result.Value {
					result.Tree,
						result.Value = candidate, value
					result.Moves = append(result.Moves, Move{b.Mask, swap, value})
					moved = true
					break
				}
			}
			if moved {
				break
			}
		}
		if !moved {
			break
		}
	}
	return result
}
func bme(t Tree, matrix [][]float64, n int) float64 {
	taxa := t.leaves(n)
	s := 0.0
	for i, a := range taxa {
		for _, b := range taxa[i+1:] {
			_, edges := path(t, a, b)
			s += matrix[a][b] / float64(uint64(1)<<uint(edges-1))
		}
	}
	return s
}
func bounds(taxa []Record, length int) (int, int, []int) {
	minimum, maximum := 0, 0
	columns := make([]int, length)
	for col := 0; col < length; col++ {
		best := 5
		for mask := 1; mask <= 15; mask++ {
			valid := true
			for _, t := range taxa {
				if mask&baseSets[t.Sequence[col]] == 0 {
					valid = false
					break
				}
			}
			if valid {
				best = min(best,
					popcount(mask))
			}
		}
		columns[col] = best - 1
		minimum += best - 1
		maxChanges := len(taxa)
		for b := 1; b <= 8; b <<= 1 {
			count := 0
			for _, t := range taxa {
				if baseSets[t.Sequence[col]]&b == 0 {
					count++
				}
			}
			maxChanges = min(maxChanges, count)
		}
		maximum += maxChanges
	}
	return minimum,
		maximum, columns
}
func consensus(clades map[int]bool, list []int, taxa []Record, outgroup int) Tree {
	t := newTree(len(taxa))
	root := t.Next
	t.Next++
	mask := 0
	for _, x := range list {
		if x != outgroup {
			mask |= 1 << x
		}
	}
	t.connect(root, outgroup, 0)
	var build func(int, int)
	build = func(node,
		current int) {
		var maximal []int
		for c := range clades {
			if c != current && c&current == c {
				contained := false
				for d := range clades {
					if d != c && d != current && d&current == d && c&d == c {
						contained = true
						break
					}
				}
				if !contained {
					maximal = append(maximal,
						c)
				}
			}
		}
		sort.Ints(maximal)
		covered := 0
		for _, c := range maximal {
			v := t.Next
			t.Next++
			t.connect(node,
				v, 0)
			covered |= c
			build(v, c)
		}
		for _, x := range list {
			if current>>x&1 != 0 && covered>>x&1 == 0 {
				t.connect(node,
					x, 0)
			}
		}
	}
	build(root, mask)
	return t
}
func exhaustive(list []int, taxa []Record, outgroup, length int, matrix [][]float64) []ExhaustiveTree {
	t := newTree(len(taxa))
	u := t.Next
	t.Next++
	for _, x := range list[:3] {
		t.connect(u, x, 0)
	}
	trees := []Tree{t}
	for _, x := range list[3:] {
		var next []Tree
		for _, tree := range trees {
			for _, branch := range branches(tree, taxa, outgroup) {
				next = append(next, insertion(tree,
					branch, x))
			}
		}
		trees = next
	}
	a := make([]ExhaustiveTree, len(trees))
	for i, t := range trees {
		a[i] = ExhaustiveTree{t,
			parsimonyScore(t, taxa, outgroup, length), bme(t, matrix, len(taxa)), newick(t, taxa, outgroup, false, nil),
			splitSet(t, taxa, outgroup)}
	}
	return a
}
func likelihood(t Tree, taxa []Record, outgroup, length int) []float64 {
	r := rootTree(t, taxa, outgroup)
	a := make([]float64,
		length)
	for col := 0; col < length; col++ {
		var visit func(int) [4]float64
		visit = func(v int) [4]float64 {
			var values [4]float64
			if v < len(taxa) {
				mask := baseSets[taxa[v].Sequence[col]]
				for x := 0; x < 4; x++ {
					if mask>>x&1 != 0 {
						values[x] = 1
					}
				}
				return values
			}
			for x := range values {
				values[x] = 1
			}
			for _, child := range r.Children[v] {
				partial := visit(child)
				e := math.Exp(-4 * t.Adj[v][child] / 3)
				same, different := 0.25+0.75*e,
					0.25-0.25*e
				for x := 0; x < 4; x++ {
					sum := 0.0
					for y := 0; y < 4; y++ {
						p := different
						if x == y {
							p = same
						}
						sum += p * partial[y]
					}
					values[x] *= sum
				}
			}
			return values
		}
		root := visit(r.Root)
		sum := 0.0
		for x := 0; x < 4; x++ {
			sum += 0.25 * root[x]
		}
		a[col] = math.Log(sum)
	}
	return a
}
func rf(a, b map[int]bool) int {
	n := 0
	for m := range a {
		if !b[m] {
			n++
		}
	}
	for m := range b {
		if !a[m] {
			n++
		}
	}
	return n
}
func quartet(splits map[int]bool, a, b, c, d int) int {
	partitions := [][4]int{{a, b, c, d}, {a, c, b, d}, {a, d,
		b, c}}
	for k, p := range partitions {
		for mask := range splits {
			left := mask >> p[0] & 1
			right := mask >> p[2] & 1
			if left == mask>>p[1]&1 && right == mask>>p[3]&1 && left != right {
				return k + 1
			}
		}
	}
	return 0
}
func quartetDistance(a, b map[int]bool, n int) int {
	count := 0
	for i := 0; i < n; i++ {
		for j := i + 1; j < n; j++ {
			for k := j + 1; k < n; k++ {
				for l := k + 1; l < n; l++ {
					if quartet(a,
						i, j, k, l) != quartet(b, i, j, k, l) {
						count++
					}
				}
			}
		}
	}
	return count
}
func sum(a []float64) float64 {
	s := 0.0
	for _, v := range a {
		s += v
	}
	return s
}
func matrixLines(out *strings.Builder, d [][]float64, taxa []Record) {
	width := 0
	for _, t := range taxa {
		width = max(width,
			len(t.Name))
	}
	for i, t := range taxa {
		fmt.Fprintf(out, "%-*s", width, t.Name)
		for j := range taxa {
			fmt.Fprintf(out,
				" %s", format(d[i][j], 5))
		}
		out.WriteByte('\n')
	}
}
func main() {
	records := readFASTA()
	missing := 0
	for _, s := range strings.Split(strings.TrimSpace(readText("input/params.txt")),
		"\n") {
		a := strings.Fields(s)
		if a[0] == "max_missing_percent" {
			missing = integer(a[1])
		}
	}
	taxa, errors := checkAlignment(records,
		missing)
	p := readSettings(taxa)
	n, length := len(taxa), len(records[0].Sequence)
	list, ingroup := make([]int,
		n), []int{}
	for i := range list {
		list[i] = i
		if i != p.Outgroup {
			ingroup = append(ingroup, i)
		}
	}
	order := append([]int{p.Outgroup},
		ingroup...)
	exOrder := []int{p.Outgroup}
	exMask := 0
	for _, x := range p.Exhaustive {
		if x != p.Outgroup {
			exOrder = append(exOrder,
				x)
			exMask |= 1 << x
		}
	}
	patternStrings, patternCount := patterns(taxa, length)
	weights := make([]int, length)
	for i := range weights {
		weights[i] = 1
	}
	modelNames := []string{"P",
		"JC", "K2P"}
	methodNames := []string{"NJ_P", "NJ_JC", "NJ_K2P", "ME", "MP", "CONSENSUS"}
	mainIndex := 0
	matrices := make([][][]float64,
		3)
	trees := make([]Tree, 6)
	for i, name := range modelNames {
		matrices[i] = distanceMatrix(taxa, weights,
			name, p.Saturation)
		trees[i] = neighborJoining(matrices[i], list, n)
		if name == p.Model {
			mainIndex = i
		}
	}
	mainMatrix,
		mainTree := matrices[mainIndex], trees[mainIndex]
	mainName := methodNames[mainIndex]
	mainSplits := splitSet(mainTree,
		taxa, p.Outgroup)
	minimum, maximum, minColumns := bounds(taxa, length)
	mpStep := stepwise(order, taxa,
		p.Outgroup, length)
	mpSearch := hillClimb(mpStep.Tree, taxa, p.Outgroup, func(t Tree) float64 {
		return float64(parsimonyScore(t,
			taxa, p.Outgroup, length))
	})
	mp, ancestors, changes, mpColumns := reconstruct(mpSearch.Tree, taxa, p.Outgroup,
		length)
	trees[4] = mp
	me := hillClimb(mainTree, taxa, p.Outgroup, func(t Tree) float64 {
		return bme(t, mainMatrix,
			n)
	})
	trees[3] = me.Tree
	allTrees := exhaustive(exOrder, taxa, p.Outgroup, length, mainMatrix)
	bestScore := allTrees[0].Score
	for _, t := range allTrees {
		bestScore = min(bestScore, t.Score)
	}
	var optimal []ExhaustiveTree
	scoreCounts := map[int]int{}
	for _, t := range allTrees {
		scoreCounts[t.Score]++
		if t.Score == bestScore {
			optimal = append(optimal, t)
		}
	}
	sort.Slice(optimal,
		func(i, j int) bool { return optimal[i].Newick < optimal[j].Newick })
	strictClades := map[int]bool{}
	for mask := range optimal[0].Splits {
		strictClades[mask] = true
	}
	for _, t := range optimal[1:] {
		for mask := range strictClades {
			if !t.Splits[mask] {
				delete(strictClades, mask)
			}
		}
	}
	strict := consensus(strictClades,
		exOrder, taxa, p.Outgroup)
	bmeTrees := append([]ExhaustiveTree(nil), allTrees...)
	sort.Slice(bmeTrees,
		func(i, j int) bool {
			a, b := bmeTrees[i], bmeTrees[j]
			return a.BME < b.BME || a.BME == b.BME && a.Newick < b.Newick
		})
	validationStep := stepwise(exOrder,
		taxa, p.Outgroup, length)
	validationSearch := hillClimb(validationStep.Tree, taxa, p.Outgroup, func(t Tree) float64 {
		return float64(parsimonyScore(t,
			taxa, p.Outgroup, length))
	})
	loglik := make([][]float64, 3)
	for i := 0; i < 3; i++ {
		loglik[i] = likelihood(trees[i],
			taxa, p.Outgroup, length)
	}
	var summary, distancesOut, newicks, cladograms, parsimonyOut, likelihoodOut, bootstrap, clock, comparison,
		hypotheses strings.Builder
	line(&summary, "INPUT records %d accepted %d rejected %d columns %d",
		len(records), n, len(errors), length)
	for _, e := range errors {
		line(&summary, e)
	}
	var composition [4]int
	for i, t := range taxa {
		bases, ambiguous, miss, unique, gc := 0, 0, 0, 0, 0
		for col := 0; col < length; col++ {
			c := t.Sequence[col]
			if isBase(c) {
				bases++
				if c == 'G' || c == 'C' {
					gc++
				}
				for k, b := range []byte("ACGT") {
					if c == b {
						composition[k]++
					}
				}
				otherBase, same := false, false
				for j, other := range taxa {
					if j != i && isBase(other.Sequence[col]) {
						otherBase = true
						if other.Sequence[col] == c {
							same = true
						}
					}
				}
				if otherBase && !same {
					unique++
				}
			} else if c == 'N' || c == '-' {
				miss++
			} else {
				ambiguous++
			}
		}
		line(&summary,
			"TAXON %s bases %d ambiguous %d missing %d unique %d gc %s", t.Name, bases, ambiguous, miss, unique,
			format(float64(gc)/float64(bases), 4))
	}
	classification := classify(taxa, length)
	line(&summary,
		"COLUMNS constant %d variable %d informative %d gapped %d empty %d", classification.Constant,
		classification.Variable, classification.Informative, classification.Gapped, classification.Empty)
	line(&summary,
		"PATTERNS %d", patternCount)
	totalBases := 0
	for _, v := range composition {
		totalBases += v
	}
	line(&summary,
		"COMPOSITION A %s C %s G %s T %s", format(float64(composition[0])/float64(totalBases), 4), format(float64(composition[1])/float64(totalBases),
			4), format(float64(composition[2])/float64(totalBases), 4), format(float64(composition[3])/float64(totalBases),
			4))
	total := PairCounts{}
	for i := 0; i < n; i++ {
		for j := i + 1; j < n; j++ {
			c := tally(taxa[i].Sequence, taxa[j].Sequence,
				weights)
			line(&distancesOut, "PAIR %s %s sites %d transitions %d transversions %d", taxa[i].Name,
				taxa[j].Name, c.N, c.S, c.V)
			total.N += c.N
			total.S += c.S
			total.V += c.V
		}
	}
	line(&distancesOut, "TOTAL sites %d transitions %d transversions %d",
		total.N, total.S, total.V)
	for i, name := range modelNames {
		line(&distancesOut, "")
		line(&distancesOut,
			"MODEL %s", name)
		matrixLines(&distancesOut, matrices[i], taxa)
		for a := 0; a < n; a++ {
			for b := a + 1; b < n; b++ {
				c := tally(taxa[a].Sequence,
					taxa[b].Sequence, weights)
				_, saturated := distance(c, name, p.Saturation)
				if saturated {
					line(&distancesOut,
						"SATURATED %s %s sites %d", taxa[a].Name, taxa[b].Name, c.N)
				}
			}
		}
	}
	line(&distancesOut, "")
	line(&distancesOut,
		"PATRISTIC %s", mainName)
	matrixLines(&distancesOut, patristic(mainTree, n), taxa)
	line(&distancesOut,
		"")
	line(&distancesOut, "ME start %s length %s", mainName, format(bme(mainTree, mainMatrix, n),
		5))
	for _, m := range me.Moves {
		line(&distancesOut, "NNI edge %s swap %d length %s", symbol(m.Mask,
			n), m.Swap, format(m.Value, 5))
	}
	line(&distancesOut, "ME moves %d evaluated %d length %s", len(me.Moves),
		me.Evaluated, format(me.Value, 5))
	line(&distancesOut, "EXHAUSTIVE taxa %d trees %d best %s second %s",
		len(exOrder), len(allTrees), format(bmeTrees[0].BME, 5), format(bmeTrees[1].BME, 5))
	line(&distancesOut,
		"BEST %s parsimony %d", bmeTrees[0].Newick, bmeTrees[0].Score)
	line(&parsimonyOut, "BOUNDS minimum %d maximum %d", minimum, maximum)
	for i := 0; i < 3; i++ {
		s := parsimonyScore(trees[i],
			taxa, p.Outgroup, length)
		line(&parsimonyOut, "TREE %s score %d ci %s ri %s", methodNames[i],
			s, format(float64(minimum)/float64(s), 4), format(float64(maximum-s)/float64(maximum-minimum),
				4))
	}
	line(&parsimonyOut, "START %s %s %s score %d", taxa[order[0]].Name, taxa[order[1]].Name,
		taxa[order[2]].Name, mpStep.InitialScore)
	for _, a := range mpStep.Additions {
		line(&parsimonyOut,
			"ADD %s edge %s score %d ties %d", taxa[a.Taxon].Name, symbol(a.Mask, n), a.Score, a.Ties)
	}
	line(&parsimonyOut,
		"STEPWISE score %d evaluated %d", mpStep.Score, mpStep.Evaluated)
	for _, m := range mpSearch.Moves {
		line(&parsimonyOut,
			"NNI edge %s swap %d score %d", symbol(m.Mask, n), m.Swap, int(m.Value))
	}
	mpScore := int(mpSearch.Value)
	line(&parsimonyOut,
		"SEARCH moves %d evaluated %d score %d", len(mpSearch.Moves), mpSearch.Evaluated, mpScore)
	line(&parsimonyOut,
		"TREE MP score %d ci %s ri %s", mpScore, format(float64(minimum)/float64(mpScore), 4), format(float64(maximum-mpScore)/float64(maximum-minimum),
			4))
	line(&parsimonyOut, "MP %s", newick(mp, taxa, p.Outgroup, true, nil))
	columnCounts := map[int]int{}
	most,
		homoplasy := 0, 0
	for col, k := range mpColumns {
		columnCounts[k]++
		most = max(most, k)
		if k > minColumns[col] {
			homoplasy++
		}
	}
	for k := 0; k <= most; k++ {
		line(&parsimonyOut,
			"CHANGES %d columns %d", k, columnCounts[k])
	}
	line(&parsimonyOut, "HOMOPLASY columns %d extra %d",
		homoplasy, mpScore-minimum)
	ancestorMasks := map[int]bool{}
	for mask := range ancestors {
		ancestorMasks[mask] = true
	}
	for _, mask := range sortedMasks(ancestorMasks, n) {
		line(&parsimonyOut, "ANCESTOR %s %s", symbol(mask,
			n), ancestors[mask])
	}
	line(&parsimonyOut, "")
	line(&parsimonyOut, "EXHAUSTIVE taxa %d trees %d best %d optimal %d",
		len(exOrder), len(allTrees), bestScore, len(optimal))
	var scores []int
	for s := range scoreCounts {
		scores = append(scores,
			s)
	}
	sort.Ints(scores)
	for _, s := range scores {
		line(&parsimonyOut, "SCORE %d trees %d", s, scoreCounts[s])
	}
	for _, t := range optimal {
		line(&parsimonyOut, "OPTIMAL %s bme %s", t.Newick, format(t.BME, 5))
	}
	line(&parsimonyOut,
		"STRICT %s", newick(strict, taxa, p.Outgroup, false, nil))
	line(&parsimonyOut, "HEURISTIC score %d optimal %s",
		int(validationSearch.Value), yes(int(validationSearch.Value) == bestScore))
	line(&likelihoodOut, "LIKELIHOOD columns %d patterns %d", length, patternCount)
	for i := 0; i < 3; i++ {
		total := sum(loglik[i])
		line(&likelihoodOut,
			"TREE %s loglik %s per_site %s", methodNames[i], format(total, 4), format(total/float64(length),
				4))
	}
	for _, pair := range [][2]int{{0, 1}, {0, 2}, {1, 2}} {
		a, b := pair[0], pair[1]
		delta := make([]float64,
			length)
		for col := 0; col < length; col++ {
			delta[col] = loglik[a][col] - loglik[b][col]
		}
		difference := sum(delta)
		mean := difference / float64(length)
		ss := 0.0
		for _, v := range delta {
			d := v - mean
			ss += d * d
		}
		se := math.Sqrt(float64(length) / float64(length-1) * ss)
		line(&likelihoodOut,
			"KH %s %s difference %s se %s z %s", methodNames[a], methodNames[b], format(difference, 4), format(se,
				4), format(difference/se, 4))
	}
	low := make([]int, length)
	for i := range low {
		low[i] = i
	}
	sort.SliceStable(low,
		func(i, j int) bool {
			return real(format(loglik[mainIndex][low[i]], 4)) < real(format(loglik[mainIndex][low[j]],
				4))
		})
	line(&likelihoodOut, "LOWEST %s sites %d", mainName, p.Low)
	for _, col := range low[:p.Low] {
		_,
			changes, _ := provisional(mainTree, taxa, p.Outgroup, col)
		line(&likelihoodOut, "SITE %d loglik %s changes %d pattern %s",
			col+1, format(loglik[mainIndex][col], 4), changes, patternStrings[col])
	}
	support := map[int]int{}
	line(&bootstrap, "BOOTSTRAP model %s replicates %d seed %d", p.Model, p.Replicates,
		p.Seed)
	state := int64(p.Seed)
	identical := 0
	for replicate := 1; replicate <= p.Replicates; replicate++ {
		w := make([]int,
			length)
		for draw := 0; draw < length; draw++ {
			state = 48271 * state % 2147483647
			w[int(state%int64(length))]++
		}
		distinct := 0
		for _, count := range w {
			if count > 0 {
				distinct++
			}
		}
		tree := neighborJoining(distanceMatrix(taxa, w, p.Model,
			p.Saturation), list, n)
		splits := splitSet(tree, taxa, p.Outgroup)
		for mask := range splits {
			support[mask]++
		}
		distance := rf(mainSplits,
			splits)
		if distance == 0 {
			identical++
		}
		line(&bootstrap, "REPLICATE %d distinct %d rf %d", replicate,
			distinct, distance)
	}
	line(&bootstrap, "IDENTICAL %d", identical)
	for _, mask := range sortedMasks(mainSplits,
		n) {
		line(&bootstrap, "SUPPORT %s %d", symbol(mask, n), support[mask])
	}
	allSupport := map[int]bool{}
	majority := map[int]bool{}
	for mask, count := range support {
		allSupport[mask] = true
		if 2*count > p.Replicates {
			majority[mask] = true
		}
	}
	ranked := sortedMasks(allSupport,
		n)
	sort.SliceStable(ranked, func(i, j int) bool { return support[ranked[i]] > support[ranked[j]] })
	for _, mask := range ranked {
		line(&bootstrap, "SPLIT %s %d", symbol(mask, n), support[mask])
	}
	trees[5] = consensus(majority,
		list, taxa, p.Outgroup)
	line(&bootstrap, "CONSENSUS %s", newick(trees[5], taxa, p.Outgroup, false,
		support))
	for _, removed := range ingroup {
		var keep []int
		for _, x := range list {
			if x != removed {
				keep = append(keep,
					x)
			}
		}
		tree := neighborJoining(mainMatrix, keep, n)
		restricted := map[int]bool{}
		for mask := range mainSplits {
			mask &= ^(1 << removed)
			count := popcount(mask)
			if count >= 2 && count <= n-3 {
				restricted[mask] = true
			}
		}
		line(&bootstrap,
			"JACKKNIFE %s rf %d", taxa[removed].Name, rf(restricted, splitSet(tree, taxa, p.Outgroup)))
	}
	var rateLines strings.Builder
	rejected, pairCount := 0, 0
	for i, a := range ingroup {
		for _, b := range ingroup[i+1:] {
			m1,
				m2 := 0, 0
			for col := 0; col < length; col++ {
				x, y, o := taxa[a].Sequence[col], taxa[b].Sequence[col], taxa[p.Outgroup].Sequence[col]
				if isBase(x) && isBase(y) && isBase(o) && x != y {
					if y == o {
						m1++
					}
					if x == o {
						m2++
					}
				}
			}
			difference := m1 - m2
			reject := 1000*difference*difference > 3841*(m1+m2)
			if reject {
				rejected++
			}
			pairCount++
			chi := "-"
			if m1+m2 > 0 {
				chi = format(float64(difference*difference)/float64(m1+m2),
					4)
			}
			verdict := "ok"
			if reject {
				verdict = "reject"
			}
			line(&rateLines, "RRT %s %s m1 %d m2 %d chi2 %s %s",
				taxa[a].Name, taxa[b].Name, m1, m2, chi, verdict)
		}
	}
	line(&clock, "RELATIVE_RATE outgroup %s pairs %d rejected %d",
		taxa[p.Outgroup].Name, pairCount, rejected)
	clock.WriteString(rateLines.String())
	root := rootTree(mainTree,
		taxa, p.Outgroup).Root
	tipDistances := make([]float64, len(ingroup))
	for i, x := range ingroup {
		tipDistances[i],
			_ = path(mainTree, root, x)
	}
	mu := sum(tipDistances) / float64(len(ingroup))
	ss := 0.0
	for _, x := range tipDistances {
		d := x - mu
		ss += d * d
	}
	sd := math.Sqrt(ss / float64(len(ingroup)-1))
	line(&clock,
		"ROOT_TO_TIP %s mean %s sd %s cv %s", mainName, format(mu, 5), format(sd, 5), format(sd/mu, 4))
	for i, x := range ingroup {
		line(&clock, "TIP %s %s", taxa[x].Name, format(tipDistances[i], 5))
	}
	splits := make([]map[int]bool, 6)
	allClades := map[int]bool{}
	mainLengths := map[int]float64{}
	for _, branch := range branches(mainTree,
		taxa, p.Outgroup) {
		mainLengths[branch.Mask] = mainTree.Adj[branch.U][branch.V]
	}
	mpBranchMasks := map[int]bool{}
	for _, branch := range branches(mp, taxa, p.Outgroup) {
		mpBranchMasks[branch.Mask] = true
	}
	for i, t := range trees {
		splits[i] = splitSet(t,
			taxa, p.Outgroup)
		supported := 0
		for mask := range splits[i] {
			allClades[mask] = true
			if 2*support[mask] > p.Replicates {
				supported++
			}
		}
		parsimonyValue,
			bmeValue, treeLength, negative, sseValue, likelihoodValue := "-", "-", "-", "-", "-", "-"
		if i < 5 {
			parsimonyValue = fmt.Sprint(parsimonyScore(t,
				taxa, p.Outgroup, length))
			bmeValue = format(bme(t, mainMatrix, n), 5)
		}
		if i < 3 {
			total := 0.0
			for _, branch := range branches(t, taxa, p.Outgroup) {
				total += t.Adj[branch.U][branch.V]
			}
			treeLength = format(total,
				5)
			negative = fmt.Sprint(t.Negative)
			ss := 0.0
			for a := 0; a < n; a++ {
				for b := a + 1; b < n; b++ {
					patristic,
						_ := path(t, a, b)
					delta := matrices[i][a][b] - patristic
					ss += delta * delta
				}
			}
			sseValue = format(ss, 6)
			likelihoodValue = format(sum(loglik[i]),
				4)
		}
		if i == 4 {
			treeLength = format(float64(mpScore)/float64(length), 5)
		}
		line(&comparison, "TREE %s splits %d supported %d parsimony %s bme %s length %s negative %s sse %s loglik %s",
			methodNames[i], len(splits[i]), supported, parsimonyValue, bmeValue, treeLength, negative, sseValue,
			likelihoodValue)
		withLengths := i < 3 || i == 4
		var counts map[int]int
		if i == 5 {
			counts = support
		}
		line(&newicks,
			"%s %s", methodNames[i], newick(t, taxa, p.Outgroup, withLengths, counts))
		if i > 0 {
			line(&cladograms,
				"")
		}
		line(&cladograms, "TREE %s", methodNames[i])
		cladogram(&cladograms, t, taxa, p.Outgroup, support)
	}
	for k, label := range []string{"RF", "QUARTET"} {
		line(&comparison, "%s %s", label, strings.Join(methodNames,
			" "))
		for i, name := range methodNames {
			values := []string{name}
			for j := range trees {
				value := rf(splits[i],
					splits[j])
				if k == 1 {
					value = quartetDistance(splits[i], splits[j], n)
				}
				values = append(values, fmt.Sprint(value))
			}
			line(&comparison,
				strings.Join(values, " "))
		}
	}
	for _, mask := range sortedMasks(allClades, n) {
		marks := make([]byte,
			6)
		for i := range marks {
			marks[i] = '-'
			if splits[i][mask] {
				marks[i] = '+'
			}
		}
		branchLength, branchChanges := "-",
			"-"
		if value, found := mainLengths[mask]; found {
			branchLength = format(value, 5)
		}
		if mpBranchMasks[mask] {
			branchChanges = fmt.Sprint(changes[mask])
		}
		line(&comparison,
			"CLADE %s support %d trees %s length %s changes %s", symbol(mask, n), support[mask], string(marks),
			branchLength, branchChanges)
	}
	nameToTaxon := map[string]int{}
	for i, t := range taxa {
		nameToTaxon[t.Name] = i
	}
	allIngroup := 0
	for _, x := range ingroup {
		allIngroup |= 1 << x
	}
	for _, h := range p.Hypotheses {
		name := h[0]
		mask := 0
		reason := ""
		for _, name := range h[1:] {
			i, found := nameToTaxon[name]
			if !found {
				reason = "unknown taxon " + name
				break
			}
			mask |= 1 << i
		}
		if reason == "" && mask>>p.Outgroup&1 != 0 {
			reason = "contains outgroup"
		}
		if reason != "" {
			line(&hypotheses,
				"INVALID %s %s", name, reason)
			continue
		}
		line(&hypotheses, "CLADE %s taxa %d support %d", name,
			popcount(mask), support[mask])
		for i, method := range methodNames {
			mrca := allIngroup
			for clade := range splits[i] {
				if clade&mask == mask && popcount(clade) < popcount(mrca) {
					mrca = clade
				}
			}
			var intruders []string
			for x, t := range taxa {
				if mrca>>x&1 != 0 && mask>>x&1 == 0 {
					intruders = append(intruders, t.Name)
				}
			}
			intruderList := "-"
			if len(intruders) > 0 {
				intruderList = strings.Join(intruders,
					",")
			}
			line(&hypotheses, "TEST %s %s monophyletic %s mrca %d intruders %s", name, method, yes(mrca == mask),
				popcount(mrca), intruderList)
		}
		subset := mask & exMask
		count := popcount(subset)
		if count < 2 || count >= len(exOrder)-1 {
			line(&hypotheses,
				"SUBSET %s untestable", name)
			continue
		}
		with, without := int(^uint(0)>>1), int(^uint(0)>>1)
		bmeWith,
			bmeWithout := math.MaxFloat64, math.MaxFloat64
		for _, t := range allTrees {
			if t.Splits[subset] {
				with = min(with,
					t.Score)
				bmeWith = math.Min(bmeWith, t.BME)
			} else {
				without = min(without, t.Score)
				bmeWithout = math.Min(bmeWithout,
					t.BME)
			}
		}
		line(&hypotheses, "SUBSET %s taxa %d with %d without %d bme_with %s bme_without %s",
			name, count, with, without, format(bmeWith, 5), format(bmeWithout, 5))
	}
	must(os.MkdirAll("output",
		0755))
	for name, s := range map[string]*strings.Builder{"summary.txt": &summary, "distances.txt": &distancesOut,
		"trees.nwk": &newicks, "cladograms.txt": &cladograms, "parsimony.txt": &parsimonyOut, "likelihood.txt": &likelihoodOut,
		"bootstrap.txt": &bootstrap, "clock.txt": &clock, "comparison.txt": &comparison, "hypotheses.txt": &hypotheses} {
		write("output/"+name,
			s)
	}
}
