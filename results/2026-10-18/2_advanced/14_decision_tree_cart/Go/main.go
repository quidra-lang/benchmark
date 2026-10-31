package main

import (
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

type Minstd struct{ state int64 }

func (g *Minstd) draw() int64 { g.state = 48271 * g.state % 2147483647; return g.state }
func countsText(counts []int64) string {
	fields := make([]string, len(counts))
	for i, count := range counts {
		fields[i] = strconv.FormatInt(count, 10)
	}
	return strings.Join(fields, " ")
}
func joinSections(sections ...[]string) []string {
	lines := []string{}
	for i, section := range sections {
		if i > 0 {
			lines = append(lines, "")
		}
		lines = append(lines, section...)
	}
	return lines
}
func directionText(left bool) string {
	if left {
		return "left"
	}
	return "right"
}

type Condition struct {
	attribute           *Attribute
	lower, upper, equal int
	excluded            map[int]bool
}

func (c Condition) text() string {
	name := c.attribute.name
	if c.attribute.integer {
		if c.lower >= 0 && c.upper >= 0 {
			return halfText(c.lower) + " < " + name + " <= " + halfText(c.upper)
		}
		if c.lower >= 0 {
			return name + " > " + halfText(c.lower)
		}
		return name + " <= " + halfText(c.upper)
	}
	if c.equal >= 0 {
		return name + " = " + c.attribute.values[c.equal]
	}
	names := []string{}
	for value, name := range c.attribute.values {
		if c.excluded[value] {
			names = append(names, name)
		}
	}
	if len(names) == 1 {
		return name + " != " + names[0]
	}
	return name + " not in {" + strings.Join(names, ",") + "}"
}
func (c Condition) holds(row Row) bool {
	value := row.values[c.attribute.index]
	if value < 0 {
		return false
	}
	if c.attribute.integer {
		return (c.lower < 0 || 2*value > c.lower) && (c.upper < 0 || 2*value <= c.upper)
	}
	if c.equal >= 0 {
		return value == c.equal
	}
	return !c.excluded[value]
}

type RuleStep struct {
	split Split
	left  bool
}
type Rule struct {
	number              int
	leaf                *Node
	conditions, general []Condition
	removed             []string
}

func simplify(steps []RuleStep, attributes []*Attribute) []Condition {
	result := []Condition{}
	for _, attribute := range attributes {
		condition := Condition{attribute, -1, -1, -1, map[int]bool{}}
		found := false
		for _, step := range steps {
			if step.split.attribute.index != attribute.index {
				continue
			}
			found = true
			point := step.split.point
			if attribute.integer {
				if step.left {
					if condition.upper < 0 || point < condition.upper {
						condition.upper = point
					}
				} else if point > condition.lower {
					condition.lower = point
				}
			} else if step.left {
				condition.equal = point
			} else {
				condition.excluded[point] = true
			}
		}
		if found {
			result = append(result, condition)
		}
	}
	return result
}
func conditionsText(conditions []Condition) string {
	if len(conditions) == 0 {
		return "true"
	}
	fields := make([]string, len(conditions))
	for i, condition := range conditions {
		fields[i] = condition.text()
	}
	return strings.Join(fields, " and ")
}
func coverage(conditions []Condition, rows []Row, label int) (int64, int64) {
	hits, covered := int64(0), int64(0)
	for _, row := range rows {
		holds := true
		for _, condition := range conditions {
			if !condition.holds(row) {
				holds = false
				break
			}
		}
		if holds {
			covered++
			if row.label == label {
				hits++
			}
		}
	}
	return hits, covered
}
func laplace(conditions []Condition, rows []Row, label, classes int) Fraction {
	hits, covered := coverage(conditions, rows, label)
	return Fraction{hits + 1, covered + int64(classes)}
}
func omitCondition(conditions []Condition, index int) []Condition {
	result := append([]Condition(nil), conditions[:index]...)
	return append(result, conditions[index+1:]...)
}
func generalize(conditions []Condition, rows []Row, label, classes int) ([]Condition, []string) {
	current := append([]Condition(nil), conditions...)
	removed := []string{}
	for len(current) > 0 {
		estimate := laplace(current, rows, label, classes)
		bestIndex := -1
		best := Fraction{}
		for index := range current {
			value := laplace(omitCondition(current, index), rows, label, classes)
			if bestIndex < 0 || compareFractions(value, best) > 0 {
				bestIndex, best = index, value
			}
		}
		if compareFractions(estimate, best) > 0 {
			break
		}
		removed = append(removed, current[bestIndex].attribute.name)
		current = omitCondition(current, bestIndex)
	}
	return current, removed
}

type DepthResult struct {
	depth   int
	tree    Tree
	correct int64
}
type Bag struct {
	tree               Tree
	distinct, outOfBag int
	correct            int64
}
type Permutation struct {
	attribute *Attribute
	counts    []int64
	drop      int64
}
type Analysis struct {
	data                *Dataset
	builder             *TreeBuilder
	grown, pruned       Tree
	decisions           []Decision
	rules               []Rule
	bounds              []int
	foldTrees           []Tree
	depths              []DepthResult
	selectedDepth       int
	sequence            []SequenceTree
	selectedIndex       int
	bags                []Bag
	oobVotes, testVotes [][]int64
	predictions         map[string][]int
}

func newAnalysis(data *Dataset) *Analysis {
	a := &Analysis{data: data, builder: &TreeBuilder{data.attributes, len(data.classes), data.settings}, predictions: map[string][]int{}}
	a.grown = Tree{a.builder.grow(data.train), nil}
	a.pruned, a.decisions = reducedErrorPruning(a.grown.root, data.validation)
	a.buildRules()
	for fold := 0; fold <= data.settings.folds; fold++ {
		a.bounds = append(a.bounds, fold*len(data.train)/data.settings.folds)
	}
	for fold := 1; fold <= data.settings.folds; fold++ {
		training := append([]Row(nil), data.train[:a.bounds[fold-1]]...)
		training = append(training, data.train[a.bounds[fold]:]...)
		a.foldTrees = append(a.foldTrees, Tree{a.builder.grow(training), nil})
	}
	for depth := 0; depth <= data.settings.maxDepth; depth++ {
		correct := int64(0)
		for i, tree := range a.foldTrees {
			correct += limited(tree, depth).correct(a.foldRows(i + 1))
		}
		a.depths = append(a.depths, DepthResult{depth, limited(a.grown, depth), correct})
		if correct > a.depths[a.selectedDepth].correct {
			a.selectedDepth = depth
		}
	}
	a.sequence = costComplexitySequence(a.grown.root)
	for i, step := range a.sequence {
		if a.validationErrors(step.tree) <= a.validationErrors(a.sequence[a.selectedIndex].tree) {
			a.selectedIndex = i
		}
	}
	a.bagging()
	a.testVotes = make([][]int64, len(data.test))
	for i, row := range data.test {
		a.testVotes[i] = make([]int64, len(data.classes))
		for _, bag := range a.bags {
			a.testVotes[i][bag.tree.predict(row)]++
		}
	}
	models := []struct {
		name string
		tree Tree
	}{{"grown", a.grown}, {"pruned", a.pruned}, {"depth", a.depths[a.selectedDepth].tree}, {"cost_complexity", a.sequence[a.selectedIndex].tree}}
	for _, model := range models {
		for _, row := range data.test {
			a.predictions[model.name] = append(a.predictions[model.name], model.tree.predict(row))
		}
	}
	for _, votes := range a.testVotes {
		a.predictions["bagging"] = append(a.predictions["bagging"], majority(votes))
	}
	return a
}
func limited(tree Tree, depth int) Tree {
	cuts := map[int]bool{}
	for _, node := range tree.internal() {
		if node.depth == depth {
			cuts[node.number] = true
		}
	}
	return Tree{tree.root, cuts}
}
func (a *Analysis) foldRows(fold int) []Row { return a.data.train[a.bounds[fold-1]:a.bounds[fold]] }
func (a *Analysis) validationErrors(tree Tree) int64 {
	return int64(len(a.data.validation)) - tree.correct(a.data.validation)
}
func (a *Analysis) accuracy(tree Tree, rows []Row) string {
	return ratioText(tree.correct(rows), int64(len(rows)))
}
func (a *Analysis) buildRules() {
	var collect func(*Node, []RuleStep)
	collect = func(node *Node, steps []RuleStep) {
		if a.pruned.isLeaf(node) {
			conditions := simplify(steps, a.data.attributes)
			general, removed := generalize(conditions, a.data.validation, node.stats.majority, len(a.data.classes))
			a.rules = append(a.rules, Rule{len(a.rules) + 1, node, conditions, general, removed})
			return
		}
		left := append(append([]RuleStep(nil), steps...), RuleStep{*node.split, true})
		right := append(append([]RuleStep(nil), steps...), RuleStep{*node.split, false})
		collect(node.left, left)
		collect(node.right, right)
	}
	collect(a.pruned.root, nil)
}
func (a *Analysis) bagging() {
	generator := Minstd{a.data.settings.bagSeed}
	size := len(a.data.train)
	a.oobVotes = make([][]int64, size)
	for i := range a.oobVotes {
		a.oobVotes[i] = make([]int64, len(a.data.classes))
	}
	for bag := 0; bag < a.data.settings.bagTrees; bag++ {
		sample := make([]Row, size)
		seen := map[int]bool{}
		for i := range sample {
			index := int(generator.draw() % int64(size))
			sample[i] = a.data.train[index]
			seen[index] = true
		}
		tree := Tree{a.builder.grow(sample), nil}
		outside := 0
		correct := int64(0)
		for i, row := range a.data.train {
			if seen[i] {
				continue
			}
			outside++
			prediction := tree.predict(row)
			a.oobVotes[i][prediction]++
			if prediction == row.label {
				correct++
			}
		}
		a.bags = append(a.bags, Bag{tree, len(seen), outside, correct})
	}
}
func (a *Analysis) treeLines(tree Tree) []string {
	lines := []string{}
	var visit func(*Node, string)
	visit = func(node *Node, condition string) {
		line := fmt.Sprintf("%s%d %s n %d counts %s", strings.Repeat("  ", node.depth), node.number, condition, node.stats.size, countsText(node.stats.counts))
		if tree.isLeaf(node) {
			lines = append(lines, line+" leaf "+a.data.classes[node.stats.majority])
			return
		}
		lines = append(lines, line)
		visit(node.left, node.split.condition(true))
		visit(node.right, node.split.condition(false))
	}
	visit(tree.root, "root")
	nodes, leaves, depth := tree.preorder(nil), tree.leaves(), tree.depth()
	lines = append(lines, "", fmt.Sprintf("nodes %d leaves %d depth %d errors %s", len(nodes), len(leaves), depth, ratioText(tree.trainingErrors(), int64(len(a.data.train)))))
	for level := 0; level <= depth; level++ {
		count, leafCount := 0, 0
		rows, errors := int64(0), int64(0)
		for _, node := range nodes {
			if node.depth == level {
				count++
				if tree.isLeaf(node) {
					leafCount++
					rows += node.stats.size
					errors += node.stats.errors
				}
			}
		}
		lines = append(lines, fmt.Sprintf("level %d nodes %d leaves %d rows %d errors %d", level, count, leafCount, rows, errors))
	}
	return lines
}
func (a *Analysis) rootCandidateLines() []string {
	found := []*Candidate{}
	for _, attribute := range a.data.attributes {
		if candidate := a.builder.bestForAttribute(a.data.train, attribute); candidate != nil {
			found = append(found, candidate)
		}
	}
	sort.SliceStable(found, func(i, j int) bool { return compareFractions(found[i].value, found[j].value) > 0 })
	size := int64(len(a.data.train))
	lines := []string{fmt.Sprintf("root candidates n %d counts %s", size, countsText(a.grown.root.stats.counts))}
	for rank, candidate := range found {
		value := candidate.value
		gain := float64(value.numerator)/float64(value.denominator)/float64(size) - float64(a.grown.root.stats.squares)/float64(size*size)
		lines = append(lines, fmt.Sprintf("%d %s left %d right %d gain %s", rank+1, candidate.split.condition(true), len(candidate.left), len(candidate.right), realText(gain, 6)))
	}
	return lines
}
func (a *Analysis) surrogateLines() []string {
	lines := []string{"surrogates"}
	for _, node := range a.grown.internal() {
		parts := []string{}
		for _, surrogate := range node.surrogates {
			parts = append(parts, fmt.Sprintf("%s %s %d/%d", surrogate.split.condition(true), directionText(surrogate.left), surrogate.score, node.stats.size))
		}
		listed := "none"
		if len(parts) > 0 {
			listed = strings.Join(parts, " ; ")
		}
		lines = append(lines, fmt.Sprintf("node %d split %s default %s surrogates %s", node.number, node.split.condition(true), directionText(node.defaultLeft), listed))
	}
	return lines
}
func (a *Analysis) pruningLines() []string {
	lines := []string{fmt.Sprintf("reduced_error_pruning validation %d", len(a.data.validation))}
	pruned := 0
	for _, decision := range a.decisions {
		verdict := "kept"
		if decision.pruned {
			verdict = "pruned"
			pruned++
		}
		lines = append(lines, fmt.Sprintf("node %d depth %d rows %d leaf %d subtree %d %s", decision.node.number, decision.node.depth, decision.rows, decision.leafError, decision.subtreeError, verdict))
	}
	return append(lines, fmt.Sprintf("examined %d pruned %d kept %d", len(a.decisions), pruned, len(a.decisions)-pruned))
}
func (a *Analysis) predictionLines() []string {
	lines := []string{"id,predicted,actual,grown,leaf,path,missing"}
	for _, row := range a.data.test {
		route := a.pruned.route(row)
		path := []string{}
		missing := 0
		for _, node := range route.path {
			path = append(path, strconv.Itoa(node.number))
		}
		for _, step := range route.steps {
			if step.method != "primary" {
				missing++
			}
		}
		lines = append(lines, fmt.Sprintf("%s,%s,%s,%s,%d,%s,%d", row.id, a.data.classes[route.leaf.stats.majority], a.data.classes[row.label], a.data.classes[a.grown.predict(row)], route.leaf.number, strings.Join(path, "-"), missing))
	}
	return lines
}
func (a *Analysis) ruleLines() []string {
	lines := []string{fmt.Sprintf("rules %d", len(a.rules))}
	for _, rule := range a.rules {
		hits, covered := int64(0), int64(0)
		for _, row := range a.data.test {
			if a.pruned.route(row).leaf.number == rule.leaf.number {
				covered++
				if row.label == rule.leaf.stats.majority {
					hits++
				}
			}
		}
		lines = append(lines, fmt.Sprintf("rule %d node %d if %s then %s train %s test %s", rule.number, rule.leaf.number, conditionsText(rule.conditions), a.data.classes[rule.leaf.stats.majority], ratioText(rule.leaf.stats.counts[rule.leaf.stats.majority], rule.leaf.stats.size), ratioText(hits, covered)))
	}
	return lines
}
func (a *Analysis) generalizedLines() []string {
	lines := []string{fmt.Sprintf("generalized %d", len(a.rules))}
	for _, rule := range a.rules {
		label := rule.leaf.stats.majority
		hits, covered := coverage(rule.general, a.data.validation, label)
		testHits, testCovered := coverage(rule.general, a.data.test, label)
		removed := "none"
		if len(rule.removed) > 0 {
			removed = strings.Join(rule.removed, ",")
		}
		lines = append(lines, fmt.Sprintf("general %d if %s then %s removed %s laplace %s validation %d/%d test %d/%d", rule.number, conditionsText(rule.general), a.data.classes[label], removed, fractionText(hits+1, covered+int64(len(a.data.classes)), 4), hits, covered, testHits, testCovered))
	}
	return lines
}
func (a *Analysis) misclassifiedLines() []string {
	numbers := map[int]int{}
	for _, rule := range a.rules {
		numbers[rule.leaf.number] = rule.number
	}
	records := []string{}
	for _, row := range a.data.test {
		route := a.pruned.route(row)
		if route.leaf.stats.majority == row.label {
			continue
		}
		parts := []string{}
		for _, step := range route.steps {
			text := step.node.split.condition(step.left)
			if step.method != "primary" {
				text += " [" + step.method + "]"
			}
			parts = append(parts, text)
		}
		explanation := "root"
		if len(parts) > 0 {
			explanation = strings.Join(parts, "; ")
		}
		records = append(records, fmt.Sprintf("%s actual %s predicted %s rule %d path %s", row.id, a.data.classes[row.label], a.data.classes[route.leaf.stats.majority], numbers[route.leaf.number], explanation))
	}
	return append([]string{fmt.Sprintf("misclassified %d", len(records))}, records...)
}
func (a *Analysis) dataLines() []string {
	data := a.data
	lines := []string{fmt.Sprintf("data train %d validation %d test %d attributes %d classes %d target %s", len(data.train), len(data.validation), len(data.test), len(data.attributes), len(data.classes), data.target)}
	train, validation, test := statistics(data.train, len(data.classes)), statistics(data.validation, len(data.classes)), statistics(data.test, len(data.classes))
	for i, name := range data.classes {
		lines = append(lines, fmt.Sprintf("class %s train %d validation %d test %d", name, train.counts[i], validation.counts[i], test.counts[i]))
	}
	missing := make([][2]int, len(data.attributes))
	totals := [2]int{}
	for i, attribute := range data.attributes {
		for _, row := range data.validation {
			if row.values[attribute.index] < 0 {
				missing[i][0]++
				totals[0]++
			}
		}
		for _, row := range data.test {
			if row.values[attribute.index] < 0 {
				missing[i][1]++
				totals[1]++
			}
		}
	}
	lines = append(lines, fmt.Sprintf("missing validation %d test %d", totals[0], totals[1]))
	for i, attribute := range data.attributes {
		lines = append(lines, fmt.Sprintf("missing %s validation %d test %d", attribute.name, missing[i][0], missing[i][1]))
	}
	return lines
}
func (a *Analysis) summaryLine(name string, tree Tree) string {
	return fmt.Sprintf("%s nodes %d leaves %d depth %d train %s validation %s test %s", name, len(tree.preorder(nil)), len(tree.leaves()), tree.depth(), a.accuracy(tree, a.data.train), a.accuracy(tree, a.data.validation), a.accuracy(tree, a.data.test))
}
func (a *Analysis) modelEvaluation(model string) []string {
	return classificationLines(model+" test", a.data.classes, a.data.test, a.predictions[model])
}
func (a *Analysis) routingLines() []string {
	tally := map[int]map[string]int{}
	for _, node := range a.pruned.internal() {
		tally[node.number] = map[string]int{}
	}
	complete, incomplete := []Row{}, []Row{}
	for _, row := range a.data.test {
		for _, step := range a.pruned.route(row).steps {
			tally[step.node.number][step.method]++
		}
		if row.missing() == 0 {
			complete = append(complete, row)
		} else {
			incomplete = append(incomplete, row)
		}
	}
	lines := []string{"routing pruned test"}
	for _, node := range a.pruned.internal() {
		counts := tally[node.number]
		rows := counts["primary"] + counts["surrogate"] + counts["default"]
		lines = append(lines, fmt.Sprintf("node %d rows %d primary %d surrogate %d default %d", node.number, rows, counts["primary"], counts["surrogate"], counts["default"]))
	}
	return append(lines, fmt.Sprintf("complete rows %d correct %s", len(complete), a.accuracy(a.pruned, complete)), fmt.Sprintf("incomplete rows %d correct %s", len(incomplete), a.accuracy(a.pruned, incomplete)))
}
func (a *Analysis) crossValidationLines() []string {
	lines := []string{fmt.Sprintf("cross_validation folds %d", a.data.settings.folds)}
	total := int64(0)
	for i, tree := range a.foldTrees {
		rows := a.foldRows(i + 1)
		correct := tree.correct(rows)
		total += correct
		lines = append(lines, fmt.Sprintf("fold %d rows %d-%d leaves %d correct %s", i+1, a.bounds[i]+1, a.bounds[i+1], len(tree.leaves()), ratioText(correct, int64(len(rows)))))
	}
	return append(lines, "cv accuracy "+ratioText(total, int64(len(a.data.train))))
}
func (a *Analysis) depthLines() []string {
	lines := []string{"depth_selection"}
	for _, result := range a.depths {
		lines = append(lines, fmt.Sprintf("depth %d leaves %d cv %s train %s validation %s test %s", result.depth, len(result.tree.leaves()), ratioText(result.correct, int64(len(a.data.train))), a.accuracy(result.tree, a.data.train), a.accuracy(result.tree, a.data.validation), a.accuracy(result.tree, a.data.test)))
	}
	selected := a.depths[a.selectedDepth]
	return append(lines, fmt.Sprintf("selected depth %d leaves %d test %s", selected.depth, len(selected.tree.leaves()), a.accuracy(selected.tree, a.data.test)))
}
func (a *Analysis) complexityLines() []string {
	lines := []string{"cost_complexity"}
	for i, step := range a.sequence {
		alpha := fractionText(step.alpha.numerator, step.alpha.denominator*int64(len(a.data.train)), 6)
		lines = append(lines, fmt.Sprintf("subtree %d alpha %s leaves %d train_errors %d validation_errors %d", i, alpha, len(step.tree.leaves()), step.tree.trainingErrors(), a.validationErrors(step.tree)))
	}
	selected := a.sequence[a.selectedIndex].tree
	return append(lines, fmt.Sprintf("selected subtree %d leaves %d test %s", a.selectedIndex, len(selected.leaves()), a.accuracy(selected, a.data.test)))
}
func (a *Analysis) baggingLines() []string {
	settings := a.data.settings
	lines := []string{fmt.Sprintf("bagging trees %d seed %d", settings.bagTrees, settings.bagSeed)}
	for i, bag := range a.bags {
		lines = append(lines, fmt.Sprintf("bag %d distinct %d leaves %d oob %s", i+1, bag.distinct, len(bag.tree.leaves()), ratioText(bag.correct, int64(bag.outOfBag))))
	}
	hits, voted := int64(0), int64(0)
	for i, votes := range a.oobVotes {
		if sum(votes) > 0 {
			voted++
			if majority(votes) == a.data.train[i].label {
				hits++
			}
		}
	}
	lines = append(lines, fmt.Sprintf("oob accuracy %s unvoted %d", ratioText(hits, voted), int64(len(a.data.train))-voted))
	return append(lines, a.modelEvaluation("bagging")...)
}
func (a *Analysis) mcnemarLines() []string {
	lines := []string{"mcnemar pruned test"}
	for _, model := range []string{"grown", "depth", "cost_complexity", "bagging"} {
		b, c := int64(0), int64(0)
		for i, row := range a.data.test {
			pruned, other := a.predictions["pruned"][i] == row.label, a.predictions[model][i] == row.label
			if pruned && !other {
				b++
			}
			if other && !pruned {
				c++
			}
		}
		difference := b - c
		if difference < 0 {
			difference = -difference
		}
		difference = max(int64(0), difference-1)
		numerator := difference * difference
		statistic := "0/1 0.0000"
		if b+c > 0 {
			statistic = fractionText(numerator, b+c, 4)
		}
		significant := "no"
		if 1000*numerator > 3841*(b+c) {
			significant = "yes"
		}
		lines = append(lines, fmt.Sprintf("versus %s b %d c %d statistic %s significant %s", model, b, c, statistic, significant))
	}
	return lines
}
func (a *Analysis) scores(model string) [][]Fraction {
	scores := [][]Fraction{}
	if model == "bagging" {
		for _, votes := range a.testVotes {
			row := []Fraction{}
			for _, count := range votes {
				row = append(row, Fraction{count, int64(a.data.settings.bagTrees)})
			}
			scores = append(scores, row)
		}
		return scores
	}
	tree := a.grown
	if model == "pruned" {
		tree = a.pruned
	}
	for _, row := range a.data.test {
		leaf := tree.route(row).leaf
		values := []Fraction{}
		for _, count := range leaf.stats.counts {
			values = append(values, Fraction{count, leaf.stats.size})
		}
		scores = append(scores, values)
	}
	return scores
}
func (a *Analysis) aucLines() []string {
	lines := []string{}
	for _, model := range []string{"grown", "pruned", "bagging"} {
		scores := a.scores(model)
		parts := []string{"auc", model}
		macro := 0.0
		defined := 0
		for label, name := range a.data.classes {
			positives, negatives := []int{}, []int{}
			for i, row := range a.data.test {
				if row.label == label {
					positives = append(positives, i)
				} else {
					negatives = append(negatives, i)
				}
			}
			wins := int64(0)
			for _, positive := range positives {
				for _, negative := range negatives {
					comparison := compareFractions(scores[positive][label], scores[negative][label])
					if comparison > 0 {
						wins += 2
					} else if comparison == 0 {
						wins++
					}
				}
			}
			denominator := int64(2 * len(positives) * len(negatives))
			parts = append(parts, name, fractionText(wins, denominator, 4))
			if denominator > 0 {
				macro += float64(wins) / float64(denominator)
				defined++
			}
		}
		average := "-"
		if defined > 0 {
			average = realText(macro/float64(defined), 4)
		}
		parts = append(parts, "macro", average)
		lines = append(lines, strings.Join(parts, " "))
	}
	return lines
}
func (a *Analysis) learningLines() []string {
	lines := []string{"learning_curve"}
	for _, size := range a.data.settings.curve {
		grown := Tree{a.builder.grow(a.data.train[:size]), nil}
		pruned, _ := reducedErrorPruning(grown.root, a.data.validation)
		lines = append(lines, fmt.Sprintf("size %d grown leaves %d test %s pruned leaves %d test %s", size, len(grown.leaves()), a.accuracy(grown, a.data.test), len(pruned.leaves()), a.accuracy(pruned, a.data.test)))
	}
	return lines
}
func (a *Analysis) impurityLines(title string, tree Tree) []string {
	importance := make([]float64, len(a.data.attributes))
	splits := make([]int, len(importance))
	for _, node := range tree.internal() {
		index := node.split.attribute.index
		importance[index] += impurityDecrease(node.stats, node.left.stats, node.right.stats)
		splits[index]++
	}
	total := 0.0
	for _, value := range importance {
		total += value
	}
	shares := make([]float64, len(importance))
	rounded := make([]float64, len(importance))
	order := make([]int, len(importance))
	for i, value := range importance {
		order[i] = i
		if total != 0 {
			shares[i] = value / total
		}
		rounded[i], _ = strconv.ParseFloat(realText(shares[i], 4), 64)
	}
	sort.SliceStable(order, func(i, j int) bool { return rounded[order[i]] > rounded[order[j]] })
	lines := []string{"impurity " + title}
	for rank, index := range order {
		lines = append(lines, fmt.Sprintf("%d %s decrease %s share %s splits %d", rank+1, a.data.attributes[index].name, realText(importance[index]/float64(len(a.data.train)), 4), realText(shares[index], 4), splits[index]))
	}
	return lines
}
func (a *Analysis) permutationLines() []string {
	generator := Minstd{a.data.settings.permutationSeed}
	repeats, size := a.data.settings.repeats, len(a.data.test)
	base := a.pruned.correct(a.data.test)
	results := []Permutation{}
	for _, attribute := range a.data.attributes {
		counts := []int64{}
		for repeat := 0; repeat < repeats; repeat++ {
			values := make([]int, size)
			for i, row := range a.data.test {
				values[i] = row.values[attribute.index]
			}
			for position := size; position >= 2; position-- {
				other := int(generator.draw() % int64(position))
				values[position-1], values[other] = values[other], values[position-1]
			}
			rows := make([]Row, size)
			for i, row := range a.data.test {
				copied := append([]int(nil), row.values...)
				copied[attribute.index] = values[i]
				rows[i] = Row{row.id, copied, row.label}
			}
			counts = append(counts, a.pruned.correct(rows))
		}
		results = append(results, Permutation{attribute, counts, int64(repeats)*base - sum(counts)})
	}
	sort.SliceStable(results, func(i, j int) bool { return results[i].drop > results[j].drop })
	lines := []string{fmt.Sprintf("permutation pruned test repeats %d seed %d base %s", repeats, a.data.settings.permutationSeed, ratioText(base, int64(size)))}
	for rank, result := range results {
		lines = append(lines, fmt.Sprintf("%d %s correct %s drop %s", rank+1, result.attribute.name, countsText(result.counts), fractionText(result.drop, int64(repeats*size), 4)))
	}
	return lines
}
func writeLines(name string, lines []string) {
	if err := os.WriteFile("output/"+name, []byte(strings.Join(lines, "\n")+"\n"), 0644); err != nil {
		panic(err)
	}
}
func main() {
	analysis := newAnalysis(loadDataset())
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	writeLines("tree.txt", joinSections(analysis.rootCandidateLines(), analysis.treeLines(analysis.grown), analysis.surrogateLines()))
	writeLines("pruned_tree.txt", joinSections(analysis.pruningLines(), analysis.treeLines(analysis.pruned)))
	writeLines("predictions.csv", analysis.predictionLines())
	writeLines("rules.txt", joinSections(analysis.ruleLines(), analysis.generalizedLines(), analysis.misclassifiedLines()))
	writeLines("evaluation.txt", joinSections(analysis.dataLines(), []string{analysis.summaryLine("grown", analysis.grown), analysis.summaryLine("pruned", analysis.pruned)}, analysis.modelEvaluation("grown"), analysis.modelEvaluation("pruned"), analysis.routingLines(), analysis.crossValidationLines(), analysis.depthLines(), analysis.complexityLines(), analysis.baggingLines(), analysis.mcnemarLines(), analysis.aucLines(), analysis.learningLines()))
	writeLines("importance.txt", joinSections(analysis.impurityLines("grown", analysis.grown), analysis.impurityLines("pruned", analysis.pruned), analysis.permutationLines()))
}
