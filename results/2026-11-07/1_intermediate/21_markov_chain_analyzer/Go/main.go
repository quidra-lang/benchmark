package main

import (
	"bufio"
	"fmt"
	"math/big"
	"os"
	"sort"
	"strconv"
	"strings"
)

const (
	maxStates = 10
	maxGamblerSize = 9
	modulus int64 = 2147483647
	multiplier int64 = 48271
)

type Rat = *big.Rat

func zero() Rat { return new(big.Rat) }
func one() Rat { return big.NewRat(1, 1) }
func rat(n int64) Rat { return big.NewRat(n, 1) }
func add(a, b Rat) Rat { return new(big.Rat).Add(a, b) }
func sub(a, b Rat) Rat { return new(big.Rat).Sub(a, b) }
func mul(a, b Rat) Rat { return new(big.Rat).Mul(a, b) }
func div(a, b Rat) Rat { return new(big.Rat).Quo(a, b) }
func neg(a Rat) Rat { return new(big.Rat).Neg(a) }
func equal(a, b Rat) bool { return a.Cmp(b) == 0 }
func sum(values []Rat) Rat {
	total := zero()
	for _, value := range values {
		total = add(total, value)
	}
	return total
}

func fractionText(value Rat) string {
	return value.Num().String() + "/" + value.Denom().String()
}

func valueText(value Rat) string {
	whole := new(big.Int)
	remainder := new(big.Int)
	whole.DivMod(value.Num(), value.Denom(), remainder)
	digits := new(big.Int).Mul(remainder, big.NewInt(1000000))
	digits.Quo(digits, value.Denom())
	return fmt.Sprintf("%s(%s.%06d)", fractionText(value), whole.String(), digits.Int64())
}

func timeText(value Rat) string {
	if value == nil {
		return "inf"
	}
	return valueText(value)
}

func parseProbability(text string) (Rat, error) {
	parts := strings.Split(text, "/")
	numerator := new(big.Int)
	numerator.SetString(parts[0], 10)
	denominator := big.NewInt(1)
	if len(parts) == 2 {
		denominator = new(big.Int)
		denominator.SetString(parts[1], 10)
	}
	if denominator.Sign() == 0 || numerator.Cmp(denominator) > 0 {
		return nil, fmt.Errorf("BAD PROBABILITY")
	}
	return new(big.Rat).SetFrac(numerator, denominator), nil
}

func parseInt(text string) int {
	value, _ := strconv.Atoi(text)
	return value
}

func delta(i, j int) Rat {
	if i == j {
		return one()
	}
	return zero()
}

func answer(flag bool) string {
	if flag {
		return "yes"
	}
	return "no"
}

func identity(n int) [][]Rat {
	result := make([][]Rat, n)
	for i := 0; i < n; i++ {
		result[i] = make([]Rat, n)
		for j := 0; j < n; j++ {
			result[i][j] = delta(i, j)
		}
	}
	return result
}

func membership(n int, indices []int) []bool {
	inside := make([]bool, n)
	for _, i := range indices {
		inside[i] = true
	}
	return inside
}

func eliminate(matrix [][]Rat, size int) [][]Rat {
	for col := 0; col < size; col++ {
		pivotRow := col
		for matrix[pivotRow][col].Sign() == 0 {
			pivotRow++
		}
		matrix[col], matrix[pivotRow] = matrix[pivotRow], matrix[col]
		pivot := matrix[col][col]
		for k := range matrix[col] {
			matrix[col][k] = div(matrix[col][k], pivot)
		}
		for row := 0; row < size; row++ {
			if row == col {
				continue
			}
			factor := matrix[row][col]
			if factor.Sign() != 0 {
				for k := range matrix[row] {
					matrix[row][k] = sub(matrix[row][k], mul(factor, matrix[col][k]))
				}
			}
		}
	}
	result := make([][]Rat, size)
	for i := range result {
		result[i] = matrix[i][size:]
	}
	return result
}

type Chain struct {
	names []string
	positions map[string]int
	matrix [][]Rat
}

func newChain(names []string) *Chain {
	n := len(names)
	positions := make(map[string]int)
	matrix := make([][]Rat, n)
	for i, name := range names {
		positions[name] = i
		matrix[i] = make([]Rat, n)
		for j := 0; j < n; j++ {
			matrix[i][j] = zero()
		}
	}
	return &Chain{append([]string(nil), names...), positions, matrix}
}

func (chain *Chain) size() int { return len(chain.names) }
func (chain *Chain) state(text string) (int, error) {
	index, ok := chain.positions[text]
	if !ok {
		return 0, fmt.Errorf("UNKNOWN STATE %s", text)
	}
	return index, nil
}

func (chain *Chain) distinctStates(texts []string) ([]int, error) {
	indices := make([]int, 0, len(texts))
	seen := make(map[int]bool)
	for _, text := range texts {
		i, err := chain.state(text)
		if err != nil {
			return nil, err
		}
		if seen[i] {
			return nil, fmt.Errorf("DUPLICATE STATE %s", text)
		}
		seen[i] = true
		indices = append(indices, i)
	}
	return indices, nil
}

func (chain *Chain) labels(indices []int) []string {
	result := make([]string, len(indices))
	for i, index := range indices {
		result[i] = chain.names[index]
	}
	return result
}

func (chain *Chain) rowSum(i int) Rat { return sum(chain.matrix[i]) }

func (chain *Chain) blockSum(i int, block []int) Rat {
	total := zero()
	for _, j := range block {
		total = add(total, chain.matrix[i][j])
	}
	return total
}

func (chain *Chain) edge(i, j int) bool { return chain.matrix[i][j].Sign() > 0 }
func (chain *Chain) absorbing(i int) bool { return equal(chain.matrix[i][i], one()) }

func (chain *Chain) advance(distribution []Rat) []Rat {
	n := chain.size()
	result := make([]Rat, n)
	for j := 0; j < n; j++ {
		value := zero()
		for i := 0; i < n; i++ {
			value = add(value, mul(distribution[i], chain.matrix[i][j]))
		}
		result[j] = value
	}
	return result
}

func (chain *Chain) reachable(start int) []bool {
	seen := make([]bool, chain.size())
	seen[start] = true
	stack := []int{start}
	for len(stack) > 0 {
		i := stack[len(stack)-1]
		stack = stack[:len(stack)-1]
		for j := 0; j < chain.size(); j++ {
			if chain.edge(i, j) && !seen[j] {
				seen[j] = true
				stack = append(stack, j)
			}
		}
	}
	return seen
}

func gcdInt(a, b int) int {
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

type CommunicatingClass struct {
	number int
	members []int
	closed bool
	levels []int
	period int
}

func newCommunicatingClass(chain *Chain, number int, members []int) *CommunicatingClass {
	inside := membership(chain.size(), members)
	closed := true
	for _, i := range members {
		for j := 0; j < chain.size(); j++ {
			if chain.edge(i, j) && !inside[j] {
				closed = false
			}
		}
	}
	levels := make([]int, chain.size())
	for i := range levels {
		levels[i] = -1
	}
	levels[members[0]] = 0
	queue := []int{members[0]}
	for len(queue) > 0 {
		u := queue[0]
		queue = queue[1:]
		for _, v := range members {
			if chain.edge(u, v) && levels[v] < 0 {
				levels[v] = levels[u] + 1
				queue = append(queue, v)
			}
		}
	}
	period := 0
	for _, u := range members {
		for _, v := range members {
			if chain.edge(u, v) {
				period = gcdInt(period, levels[u]+1-levels[v])
			}
		}
	}
	return &CommunicatingClass{number, members, closed, levels, period}
}

type Decomposition struct {
	reach [][]bool
	classes []*CommunicatingClass
	classOf []int
}

func decompose(chain *Chain) *Decomposition {
	n := chain.size()
	d := &Decomposition{make([][]bool, n), nil, make([]int, n)}
	for i := 0; i < n; i++ {
		d.reach[i] = chain.reachable(i)
		d.classOf[i] = -1
	}
	for i := 0; i < n; i++ {
		if d.classOf[i] >= 0 {
			continue
		}
		var members []int
		for j := 0; j < n; j++ {
			if d.reach[i][j] && d.reach[j][i] {
				members = append(members, j)
				d.classOf[j] = len(d.classes)
			}
		}
		d.classes = append(d.classes, newCommunicatingClass(chain, len(d.classes)+1, members))
	}
	return d
}

func (d *Decomposition) closedClasses() []*CommunicatingClass {
	var closed []*CommunicatingClass
	for _, item := range d.classes {
		if item.closed {
			closed = append(closed, item)
		}
	}
	return closed
}

func (d *Decomposition) containing(i int) *CommunicatingClass { return d.classes[d.classOf[i]] }

func (d *Decomposition) reaches(i int, targets []bool) bool {
	for j := range targets {
		if d.reach[i][j] && targets[j] {
			return true
		}
	}
	return false
}

type Absorption struct {
	transient []int
	absorbing []int
	fundamental [][]Rat
	steps []Rat
	probabilities [][]Rat
}

func newAbsorption(chain *Chain) *Absorption {
	a := &Absorption{}
	for i := 0; i < chain.size(); i++ {
		if chain.absorbing(i) {
			a.absorbing = append(a.absorbing, i)
		} else {
			a.transient = append(a.transient, i)
		}
	}
	n := len(a.transient)
	matrix := make([][]Rat, n)
	for row, i := range a.transient {
		values := make([]Rat, 0, 2*n)
		for _, j := range a.transient {
			values = append(values, sub(delta(i, j), chain.matrix[i][j]))
		}
		for k := 0; k < n; k++ {
			values = append(values, delta(row, k))
		}
		matrix[row] = values
	}
	a.fundamental = eliminate(matrix, n)
	a.steps = make([]Rat, n)
	a.probabilities = make([][]Rat, n)
	for i, row := range a.fundamental {
		a.steps[i] = sum(row)
		for _, j := range a.absorbing {
			p := zero()
			for k := 0; k < n; k++ {
				p = add(p, mul(row[k], chain.matrix[a.transient[k]][j]))
			}
			a.probabilities[i] = append(a.probabilities[i], p)
		}
	}
	return a
}

func (a *Absorption) variance(i int) Rat {
	total := zero()
	for j := range a.transient {
		value := sub(mul(rat(2), a.fundamental[i][j]), delta(i, j))
		total = add(total, mul(value, a.steps[j]))
	}
	return sub(total, mul(a.steps[i], a.steps[i]))
}

func stationaryDistribution(chain *Chain, members []int) []Rat {
	n := len(members)
	matrix := make([][]Rat, n)
	for r := 0; r < n-1; r++ {
		for k := 0; k < n; k++ {
			matrix[r] = append(matrix[r], sub(chain.matrix[members[k]][members[r]], delta(k, r)))
		}
		matrix[r] = append(matrix[r], zero())
	}
	matrix[n-1] = make([]Rat, n+1)
	for i := range matrix[n-1] {
		matrix[n-1][i] = one()
	}
	solution := eliminate(matrix, n)
	distribution := make([]Rat, n)
	for i, row := range solution {
		distribution[i] = row[0]
	}
	return distribution
}

func irreducibleDistribution(chain *Chain, d *Decomposition) ([]Rat, error) {
	if len(d.classes) != 1 {
		return nil, fmt.Errorf("NOT IRREDUCIBLE")
	}
	return stationaryDistribution(chain, d.classes[0].members), nil
}

func solveRestricted(chain *Chain, indices []int, constants []Rat) []Rat {
	n := len(indices)
	matrix := make([][]Rat, n)
	for r, i := range indices {
		for _, j := range indices {
			matrix[r] = append(matrix[r], sub(delta(i, j), chain.matrix[i][j]))
		}
		matrix[r] = append(matrix[r], constants[r])
	}
	values := eliminate(matrix, n)
	answer := make([]Rat, n)
	for r := range values {
		answer[r] = values[r][0]
	}
	return answer
}

func hittingProbabilities(chain *Chain, d *Decomposition, targets []bool) []Rat {
	n := chain.size()
	probabilities := make([]Rat, n)
	remaining := []int{}
	constants := []Rat{}
	for i := 0; i < n; i++ {
		if targets[i] {
			probabilities[i] = one()
		} else {
			probabilities[i] = zero()
			if d.reaches(i, targets) {
				remaining = append(remaining, i)
				value := zero()
				for j := 0; j < n; j++ {
					if targets[j] {
						value = add(value, chain.matrix[i][j])
					}
				}
				constants = append(constants, value)
			}
		}
	}
	if len(remaining) != 0 {
		values := solveRestricted(chain, remaining, constants)
		for k, i := range remaining {
			probabilities[i] = values[k]
		}
	}
	return probabilities
}

func hittingTimes(chain *Chain, targets []bool, probabilities []Rat) []Rat {
	n := chain.size()
	times := make([]Rat, n)
	certain := []int{}
	constants := []Rat{}
	for i := 0; i < n; i++ {
		if targets[i] {
			times[i] = zero()
		} else if equal(probabilities[i], one()) {
			certain = append(certain, i)
			constants = append(constants, one())
		}
	}
	if len(certain) != 0 {
		values := solveRestricted(chain, certain, constants)
		for k, i := range certain {
			times[i] = values[k]
		}
	}
	return times
}

func regularExponent(chain *Chain) (int, bool) {
	n := chain.size()
	edges := make([][]bool, n)
	for i := 0; i < n; i++ {
		edges[i] = make([]bool, n)
		for j := 0; j < n; j++ {
			edges[i][j] = chain.edge(i, j)
		}
	}
	power := edges
	for exponent := 1; exponent < (n-1)*(n-1)+2; exponent++ {
		allPositive := true
		for _, row := range power {
			for _, value := range row {
				if !value {
					allPositive = false
				}
			}
		}
		if allPositive {
			return exponent, true
		}
		next := make([][]bool, n)
		for i := 0; i < n; i++ {
			next[i] = make([]bool, n)
			for j := 0; j < n; j++ {
				for k := 0; k < n; k++ {
					if power[i][k] && edges[k][j] {
						next[i][j] = true
						break
					}
				}
			}
		}
		power = next
	}
	return 0, false
}

type Analyzer struct {
	chains map[string]*Chain
	output []string
}

func newAnalyzer() *Analyzer { return &Analyzer{chains: make(map[string]*Chain)} }

func (a *Analyzer) emit(parts ...any) {
	fields := make([]string, len(parts))
	for i, part := range parts {
		fields[i] = fmt.Sprint(part)
	}
	a.output = append(a.output, strings.Join(fields, " "))
}

func (a *Analyzer) display(names []string, matrix [][]Rat, label string) {
	parts := []any{"STATES"}
	for _, name := range names {
		parts = append(parts, name)
	}
	a.emit(parts...)
	for i, row := range matrix {
		parts = []any{label, names[i]}
		for _, value := range row {
			parts = append(parts, fractionText(value))
		}
		a.emit(parts...)
	}
}

func (a *Analyzer) chain(name string) (*Chain, error) {
	c, ok := a.chains[name]
	if !ok {
		return nil, fmt.Errorf("UNKNOWN CHAIN %s", name)
	}
	return c, nil
}

func (a *Analyzer) stochastic(name string) (*Chain, error) {
	c, err := a.chain(name)
	if err != nil {
		return nil, err
	}
	for i := 0; i < c.size(); i++ {
		if !equal(c.rowSum(i), one()) {
			return nil, fmt.Errorf("NOT STOCHASTIC %s", c.names[i])
		}
	}
	return c, nil
}

func (a *Analyzer) cmdChain(args []string) error {
	name, names := args[0], args[1:]
	if len(names) > maxStates {
		return fmt.Errorf("TOO MANY STATES")
	}
	seen := make(map[string]bool)
	for _, state := range names {
		if seen[state] {
			return fmt.Errorf("DUPLICATE STATE %s", state)
		}
		seen[state] = true
	}
	a.chains[name] = newChain(names)
	a.emit("CHAIN", name, fmt.Sprintf("states=%d", len(names)))
	return nil
}

func (a *Analyzer) cmdP(args []string) error {
	c, err := a.chain(args[0])
	if err != nil {
		return err
	}
	i, err := c.state(args[1])
	if err != nil {
		return err
	}
	j, err := c.state(args[2])
	if err != nil {
		return err
	}
	p, err := parseProbability(args[3])
	if err != nil {
		return err
	}
	c.matrix[i][j] = p
	a.emit("P", args[0], args[1], args[2], fractionText(p), "rowsum="+fractionText(c.rowSum(i)))
	return nil
}

func (a *Analyzer) cmdRow(args []string) error {
	c, err := a.chain(args[0])
	if err != nil {
		return err
	}
	i, err := c.state(args[1])
	if err != nil {
		return err
	}
	if len(args)-2 != c.size() {
		return fmt.Errorf("BAD LENGTH")
	}
	values := make([]Rat, c.size())
	for j, text := range args[2:] {
		p, err := parseProbability(text)
		if err != nil {
			return err
		}
		values[j] = p
	}
	c.matrix[i] = values
	a.emit("ROW", args[0], args[1], "rowsum="+fractionText(c.rowSum(i)))
	return nil
}

func (a *Analyzer) cmdShow(args []string) error {
	c, err := a.chain(args[0])
	if err != nil {
		return err
	}
	a.emit("MATRIX", args[0], fmt.Sprintf("states=%d", c.size()))
	a.display(c.names, c.matrix, "ROW")
	return nil
}

func (a *Analyzer) cmdCheck(args []string) error {
	c, err := a.chain(args[0])
	if err != nil {
		return err
	}
	bad := []int{}
	for i := 0; i < c.size(); i++ {
		if !equal(c.rowSum(i), one()) {
			bad = append(bad, i)
		}
	}
	if len(bad) == 0 {
		a.emit("CHECK", args[0], "ok")
	} else {
		a.emit("CHECK", args[0], fmt.Sprintf("bad=%d", len(bad)))
		for _, i := range bad {
			a.emit("BADROW", c.names[i], "sum="+fractionText(c.rowSum(i)))
		}
	}
	return nil
}

func (a *Analyzer) cmdBuild(args []string) error {
	name, order := args[0], parseInt(args[1])
	if order != 1 && order != 2 {
		return fmt.Errorf("BAD ORDER")
	}
	tokens := args[2:]
	if len(tokens) <= order {
		return fmt.Errorf("TOO FEW TOKENS")
	}
	observations := []string{}
	if order == 1 {
		observations = tokens
	} else {
		for i := 1; i < len(tokens); i++ {
			observations = append(observations, tokens[i-1]+"."+tokens[i])
		}
	}
	names := []string{}
	positions := make(map[string]bool)
	for _, observation := range observations {
		if !positions[observation] {
			positions[observation] = true
			names = append(names, observation)
		}
	}
	if len(names) > maxStates {
		return fmt.Errorf("TOO MANY STATES")
	}
	c := newChain(names)
	n := c.size()
	counts := make([][]int, n)
	for i := range counts {
		counts[i] = make([]int, n)
	}
	for i := 1; i < len(observations); i++ {
		counts[c.positions[observations[i-1]]][c.positions[observations[i]]]++
	}
	a.emit("BUILD", name, fmt.Sprintf("order=%d", order), fmt.Sprintf("states=%d", n),
		fmt.Sprintf("transitions=%d", len(observations)-1))
	for i := 0; i < n; i++ {
		total := 0
		for _, count := range counts[i] {
			total += count
		}
		if total == 0 {
			c.matrix[i][i] = one()
			a.emit("FROM", names[i], "total=0", "absorbing")
			continue
		}
		parts := []any{"FROM", names[i], fmt.Sprintf("total=%d", total)}
		for j := 0; j < n; j++ {
			if counts[i][j] > 0 {
				c.matrix[i][j] = big.NewRat(int64(counts[i][j]), int64(total))
				parts = append(parts, fmt.Sprintf("%s:%d", names[j], counts[i][j]))
			}
		}
		a.emit(parts...)
	}
	a.chains[name] = c
	return nil
}

func (a *Analyzer) cmdGambler(args []string) error {
	name, goal, start := args[0], parseInt(args[1]), parseInt(args[2])
	if goal < 1 || goal > maxGamblerSize {
		return fmt.Errorf("BAD SIZE")
	}
	if start > goal {
		return fmt.Errorf("BAD START")
	}
	p, err := parseProbability(args[3])
	if err != nil {
		return err
	}
	if equal(p, zero()) || equal(p, one()) {
		return fmt.Errorf("BAD PROBABILITY")
	}
	names := make([]string, goal+1)
	for i := range names {
		names[i] = fmt.Sprintf("s%d", i)
	}
	c := newChain(names)
	c.matrix[0][0], c.matrix[goal][goal] = one(), one()
	for i := 1; i < goal; i++ {
		c.matrix[i][i+1] = p
		c.matrix[i][i-1] = sub(one(), p)
	}
	a.chains[name] = c
	absorption := newAbsorption(c)
	ruin := []Rat{one()}
	duration := []Rat{zero()}
	for i := range absorption.transient {
		ruin = append(ruin, absorption.probabilities[i][0])
		duration = append(duration, absorption.steps[i])
	}
	ruin = append(ruin, zero())
	duration = append(duration, zero())
	a.emit("GAMBLER", name, fmt.Sprintf("g=%d", goal),
		"p="+fractionText(p), fmt.Sprintf("start=s%d", start),
		"ruin="+valueText(ruin[start]), "duration="+valueText(duration[start]))
	for i := 0; i <= goal; i++ {
		a.emit("CAPITAL", fmt.Sprintf("s%d", i), "ruin="+valueText(ruin[i]),
			"win="+valueText(sub(one(), ruin[i])), "duration="+valueText(duration[i]))
	}
	return nil
}

func (a *Analyzer) cmdClasses(args []string) error {
	c, err := a.stochastic(args[0])
	if err != nil {
		return err
	}
	d := decompose(c)
	a.emit("CLASSES", args[0], fmt.Sprintf("count=%d", len(d.classes)))
	for _, item := range d.classes {
		kind := "TRANSIENT"
		if item.closed {
			kind = "RECURRENT"
		}
		parts := []any{"CLASS", item.number, kind, fmt.Sprintf("period=%d", item.period),
			fmt.Sprintf("size=%d", len(item.members))}
		for _, name := range c.labels(item.members) {
			parts = append(parts, name)
		}
		a.emit(parts...)
		if item.period < 2 {
			continue
		}
		for remainder := 0; remainder < item.period; remainder++ {
			parts = []any{"CYCLIC", remainder}
			for _, state := range item.members {
				if item.levels[state]%item.period == remainder {
					parts = append(parts, c.names[state])
				}
			}
			a.emit(parts...)
		}
	}
	return nil
}

func (a *Analyzer) cmdClassify(args []string) error {
	c, err := a.stochastic(args[0])
	if err != nil {
		return err
	}
	d := decompose(c)
	absorbing := make([]bool, c.size())
	count := 0
	for i := range absorbing {
		absorbing[i] = c.absorbing(i)
		if absorbing[i] {
			count++
		}
	}
	absorbingChain := count > 0
	for i := 0; i < c.size(); i++ {
		if !d.reaches(i, absorbing) {
			absorbingChain = false
		}
	}
	exponent, regular := regularExponent(c)
	exponentText := "-"
	if regular {
		exponentText = strconv.Itoa(exponent)
	}
	a.emit("CLASSIFY", args[0], fmt.Sprintf("absorbing_states=%d", count),
		"absorbing="+answer(absorbingChain), "ergodic="+answer(len(d.classes) == 1),
		"regular="+answer(regular), "exponent="+exponentText)
	return nil
}

func (a *Analyzer) cmdStep(args []string) error {
	c, err := a.stochastic(args[0])
	if err != nil {
		return err
	}
	initial, steps := args[1], parseInt(args[2])
	var distribution []Rat
	if len(initial) != 0 && initial[0] >= '0' && initial[0] <= '9' {
		texts := strings.Split(initial, ",")
		if len(texts) != c.size() {
			return fmt.Errorf("BAD LENGTH")
		}
		for _, text := range texts {
			p, err := parseProbability(text)
			if err != nil {
				return err
			}
			distribution = append(distribution, p)
		}
		if !equal(sum(distribution), one()) {
			return fmt.Errorf("BAD DISTRIBUTION")
		}
	} else {
		state, err := c.state(initial)
		if err != nil {
			return err
		}
		distribution = make([]Rat, c.size())
		for j := range distribution {
			distribution[j] = delta(state, j)
		}
	}
	for step := 0; step < steps; step++ {
		distribution = c.advance(distribution)
	}
	a.emit("STEP", args[0], fmt.Sprintf("k=%d", steps))
	for i, value := range distribution {
		a.emit("PROB", c.names[i], valueText(value))
	}
	return nil
}

func (a *Analyzer) cmdPower(args []string) error {
	c, err := a.stochastic(args[0])
	if err != nil {
		return err
	}
	steps := parseInt(args[1])
	matrix := identity(c.size())
	for k := 0; k < steps; k++ {
		for i, row := range matrix {
			matrix[i] = c.advance(row)
		}
	}
	a.emit("POWER", args[0], fmt.Sprintf("k=%d", steps))
	a.display(c.names, matrix, "ROW")
	return nil
}

func (a *Analyzer) cmdStationary(args []string) error {
	c, err := a.stochastic(args[0])
	if err != nil {
		return err
	}
	closed := decompose(c).closedClasses()
	a.emit("STATIONARY", args[0], fmt.Sprintf("count=%d", len(closed)))
	for number, item := range closed {
		a.emit("DIST", number+1, fmt.Sprintf("class=%d", item.number),
			fmt.Sprintf("size=%d", len(item.members)))
		values := stationaryDistribution(c, item.members)
		for i, state := range item.members {
			a.emit("PI", c.names[state], valueText(values[i]))
		}
	}
	return nil
}

func (a *Analyzer) cmdRecurrence(args []string) error {
	c, err := a.stochastic(args[0])
	if err != nil {
		return err
	}
	state, err := c.state(args[1])
	if err != nil {
		return err
	}
	item := decompose(c).containing(state)
	if !item.closed {
		return fmt.Errorf("TRANSIENT STATE %s", args[1])
	}
	values := stationaryDistribution(c, item.members)
	rho := zero()
	for i, member := range item.members {
		if member == state {
			rho = values[i]
			break
		}
	}
	a.emit("RECURRENCE", args[0], args[1],
		"pi="+valueText(rho), "mean="+valueText(div(one(), rho)),
		fmt.Sprintf("period=%d", item.period))
	return nil
}

func (a *Analyzer) cmdAbsorb(args []string) error {
	c, err := a.stochastic(args[0])
	if err != nil {
		return err
	}
	absorbing := make([]bool, c.size())
	count := 0
	for i := range absorbing {
		absorbing[i] = c.absorbing(i)
		if absorbing[i] {
			count++
		}
	}
	if count == 0 {
		return fmt.Errorf("NO ABSORBING STATE")
	}
	d := decompose(c)
	for i := 0; i < c.size(); i++ {
		if !absorbing[i] && !d.reaches(i, absorbing) {
			return fmt.Errorf("NOT ABSORBING %s", c.names[i])
		}
	}
	result := newAbsorption(c)
	a.emit("ABSORB", args[0],
		fmt.Sprintf("transient=%d", len(result.transient)),
		fmt.Sprintf("absorbing=%d", len(result.absorbing)))
	if len(result.transient) == 0 {
		return nil
	}
	transientNames := c.labels(result.transient)
	parts := []any{"TRANSIENT"}
	for _, name := range transientNames {
		parts = append(parts, name)
	}
	a.emit(parts...)
	parts = []any{"ABSORBING"}
	for _, name := range c.labels(result.absorbing) {
		parts = append(parts, name)
	}
	a.emit(parts...)
	for i, row := range result.fundamental {
		parts := []any{"N", transientNames[i]}
		for _, value := range row {
			parts = append(parts, fractionText(value))
		}
		a.emit(parts...)
	}
	for i, name := range transientNames {
		a.emit("STEPS", name, "mean="+valueText(result.steps[i]),
			"var="+valueText(result.variance(i)))
	}
	for i, row := range result.probabilities {
		parts := []any{"B", transientNames[i]}
		for _, value := range row {
			parts = append(parts, fractionText(value))
		}
		a.emit(parts...)
	}
	return nil
}

func (a *Analyzer) cmdHitting(args []string) error {
	c, err := a.stochastic(args[0])
	if err != nil {
		return err
	}
	states, err := c.distinctStates(args[1:])
	if err != nil {
		return err
	}
	targets := membership(c.size(), states)
	probabilities := hittingProbabilities(c, decompose(c), targets)
	times := hittingTimes(c, targets, probabilities)
	names := []string{}
	for i, target := range targets {
		if target {
			names = append(names, c.names[i])
		}
	}
	a.emit("HITTING", args[0], "targets="+strings.Join(names, ","))
	for i, name := range c.names {
		a.emit("HIT", name, "prob="+valueText(probabilities[i]),
			"time="+timeText(times[i]))
	}
	return nil
}

func (a *Analyzer) cmdPassage(args []string) error {
	c, err := a.stochastic(args[0])
	if err != nil {
		return err
	}
	d := decompose(c)
	pi, err := irreducibleDistribution(c, d)
	if err != nil {
		return err
	}
	times := make([][]Rat, c.size())
	for i := range times {
		times[i] = make([]Rat, c.size())
	}
	for j := 0; j < c.size(); j++ {
		targets := membership(c.size(), []int{j})
		probabilities := hittingProbabilities(c, d, targets)
		column := hittingTimes(c, targets, probabilities)
		for i := 0; i < c.size(); i++ {
			if i == j {
				times[i][j] = div(one(), pi[j])
			} else {
				times[i][j] = column[i]
			}
		}
	}
	kemeny := zero()
	for j := 1; j < c.size(); j++ {
		kemeny = add(kemeny, mul(pi[j], times[0][j]))
	}
	a.emit("PASSAGE", args[0], "kemeny="+valueText(kemeny))
	a.display(c.names, times, "M")
	return nil
}

func (a *Analyzer) cmdFirstPassage(args []string) error {
	c, err := a.stochastic(args[0])
	if err != nil {
		return err
	}
	x, err := c.state(args[1])
	if err != nil {
		return err
	}
	y, err := c.state(args[2])
	if err != nil {
		return err
	}
	steps := parseInt(args[3])
	if steps == 0 {
		return fmt.Errorf("BAD STEPS")
	}
	n := c.size()
	current := make([]Rat, n)
	for i := range current {
		current[i] = c.matrix[i][y]
	}
	first := []Rat{current[x]}
	for k := 1; k < steps; k++ {
		next := make([]Rat, n)
		for i := 0; i < n; i++ {
			p := zero()
			for j := 0; j < n; j++ {
				if j != y {
					p = add(p, mul(c.matrix[i][j], current[j]))
				}
			}
			next[i] = p
		}
		current = next
		first = append(first, current[x])
	}
	a.emit("FIRSTPASSAGE", args[0], args[1], args[2],
		fmt.Sprintf("k=%d", steps), "total="+valueText(sum(first)))
	cumulative := zero()
	for t, value := range first {
		cumulative = add(cumulative, value)
		a.emit("FP", t+1, valueText(value), "cum="+valueText(cumulative))
	}
	return nil
}

func (a *Analyzer) cmdPathProb(args []string) error {
	c, err := a.stochastic(args[0])
	if err != nil {
		return err
	}
	path := []int{}
	for _, text := range args[1:] {
		state, err := c.state(text)
		if err != nil {
			return err
		}
		path = append(path, state)
	}
	probability := one()
	zeroAt := 0
	for t := 1; t < len(path); t++ {
		probability = mul(probability, c.matrix[path[t-1]][path[t]])
		if probability.Sign() == 0 && zeroAt == 0 {
			zeroAt = t
		}
	}
	parts := []any{"PATHPROB", args[0], fmt.Sprintf("steps=%d", len(path)-1),
		"prob="+valueText(probability)}
	if zeroAt != 0 {
		parts = append(parts, fmt.Sprintf("zero_at=%d", zeroAt))
	}
	a.emit(parts...)
	return nil
}

func (a *Analyzer) cmdMostLikely(args []string) error {
	c, err := a.stochastic(args[0])
	if err != nil {
		return err
	}
	start, err := c.state(args[1])
	if err != nil {
		return err
	}
	steps := parseInt(args[2])
	if steps == 0 {
		return fmt.Errorf("BAD STEPS")
	}
	best := make([][]Rat, steps+1)
	for t := range best {
		best[t] = make([]Rat, c.size())
		for i := range best[t] {
			best[t][i] = one()
		}
	}
	for t := steps - 1; t >= 0; t-- {
		for i := 0; i < c.size(); i++ {
			top := zero()
			for j := 0; j < c.size(); j++ {
				value := mul(c.matrix[i][j], best[t+1][j])
				if value.Cmp(top) > 0 {
					top = value
				}
			}
			best[t][i] = top
		}
	}
	path := []int{start}
	for t := 0; t < steps; t++ {
		current := path[len(path)-1]
		for j := 0; j < c.size(); j++ {
			if equal(mul(c.matrix[current][j], best[t+1][j]), best[t][current]) {
				path = append(path, j)
				break
			}
		}
	}
	a.emit("MOSTLIKELY", args[0], args[1], fmt.Sprintf("k=%d", steps),
		"prob="+valueText(best[0][start]))
	parts := []any{"PATH"}
	for _, name := range c.labels(path) {
		parts = append(parts, name)
	}
	a.emit(parts...)
	return nil
}

func (a *Analyzer) cmdReversible(args []string) error {
	c, err := a.stochastic(args[0])
	if err != nil {
		return err
	}
	pi, err := irreducibleDistribution(c, decompose(c))
	if err != nil {
		return err
	}
	type violation struct {
		i, j int
		forward, backward Rat
	}
	violations := []violation{}
	for i := 0; i < c.size(); i++ {
		for j := i + 1; j < c.size(); j++ {
			forward := mul(pi[i], c.matrix[i][j])
			backward := mul(pi[j], c.matrix[j][i])
			if !equal(forward, backward) {
				violations = append(violations, violation{i, j, forward, backward})
			}
		}
	}
	if len(violations) == 0 {
		a.emit("REVERSIBLE", args[0], "yes")
		return nil
	}
	a.emit("REVERSIBLE", args[0], "no", fmt.Sprintf("violations=%d", len(violations)))
	for _, v := range violations {
		a.emit("VIOLATION", c.names[v.i], c.names[v.j],
			valueText(v.forward), valueText(v.backward))
	}
	return nil
}

func (a *Analyzer) cmdReverse(args []string) error {
	c, err := a.stochastic(args[0])
	if err != nil {
		return err
	}
	pi, err := irreducibleDistribution(c, decompose(c))
	if err != nil {
		return err
	}
	reversed := newChain(c.names)
	same := true
	for i := 0; i < c.size(); i++ {
		for j := 0; j < c.size(); j++ {
			value := div(mul(pi[j], c.matrix[j][i]), pi[i])
			reversed.matrix[i][j] = value
			if !equal(value, c.matrix[i][j]) {
				same = false
			}
		}
	}
	a.chains[args[1]] = reversed
	a.emit("REVERSE", args[0], args[1], "reversible="+answer(same))
	a.display(reversed.names, reversed.matrix, "ROW")
	return nil
}

func (a *Analyzer) cmdMixing(args []string) error {
	c, err := a.stochastic(args[0])
	if err != nil {
		return err
	}
	steps := parseInt(args[1])
	if steps == 0 {
		return fmt.Errorf("BAD STEPS")
	}
	epsilon, err := parseProbability(args[2])
	if err != nil {
		return err
	}
	pi, err := irreducibleDistribution(c, decompose(c))
	if err != nil {
		return err
	}
	matrix := identity(c.size())
	type mixingRow struct {
		step int
		distance Rat
		worst string
	}
	lines := []mixingRow{}
	mixingTime := 0
	for t := 1; t <= steps; t++ {
		for i, row := range matrix {
			matrix[i] = c.advance(row)
		}
		largest := zero()
		worst := 0
		for i, row := range matrix {
			distance := zero()
			for j := 0; j < c.size(); j++ {
				difference := sub(row[j], pi[j])
				if difference.Sign() < 0 {
					difference = neg(difference)
				}
				distance = add(distance, difference)
			}
			distance = div(distance, rat(2))
			if i == 0 || distance.Cmp(largest) > 0 {
				largest = distance
				worst = i
			}
		}
		if mixingTime == 0 && largest.Cmp(epsilon) <= 0 {
			mixingTime = t
		}
		lines = append(lines, mixingRow{t, largest, c.names[worst]})
	}
	timeText := "none"
	if mixingTime != 0 {
		timeText = strconv.Itoa(mixingTime)
	}
	a.emit("MIXING", args[0], fmt.Sprintf("k=%d", steps),
		"eps="+fractionText(epsilon), "time="+timeText)
	for _, line := range lines {
		a.emit("TV", line.step, valueText(line.distance), "from="+line.worst)
	}
	return nil
}

func (a *Analyzer) cmdLump(args []string) error {
	c, err := a.stochastic(args[0])
	if err != nil {
		return err
	}
	seen := make([]bool, c.size())
	blocks := [][]int{}
	for _, group := range strings.Split(args[2], "|") {
		block := []int{}
		for _, text := range strings.Split(group, ",") {
			index, err := c.state(text)
			if err != nil {
				return err
			}
			if seen[index] {
				return fmt.Errorf("BAD PARTITION")
			}
			seen[index] = true
			block = append(block, index)
		}
		sort.Ints(block)
		blocks = append(blocks, block)
	}
	for _, present := range seen {
		if !present {
			return fmt.Errorf("BAD PARTITION")
		}
	}
	sort.Slice(blocks, func(i, j int) bool {
		return blocks[i][0] < blocks[j][0]
	})
	for _, block := range blocks {
		representative := block[0]
		for _, target := range blocks {
			expected := c.blockSum(representative, target)
			for _, i := range block {
				actual := c.blockSum(i, target)
				if !equal(actual, expected) {
					a.emit("LUMP", args[0], "not", "lumpable",
						"block="+c.names[representative], "target="+c.names[target[0]],
						c.names[representative]+"="+valueText(expected),
						c.names[i]+"="+valueText(actual))
					return nil
				}
			}
		}
	}
	names := []string{}
	for _, block := range blocks {
		names = append(names, c.names[block[0]])
	}
	lumped := newChain(names)
	for i, block := range blocks {
		for j, target := range blocks {
			lumped.matrix[i][j] = c.blockSum(block[0], target)
		}
	}
	a.chains[args[1]] = lumped
	a.emit("LUMP", args[0], args[1], fmt.Sprintf("blocks=%d", len(blocks)))
	a.display(lumped.names, lumped.matrix, "ROW")
	return nil
}

func (a *Analyzer) cmdReward(args []string) error {
	c, err := a.stochastic(args[0])
	if err != nil {
		return err
	}
	if len(args)-2 != c.size() {
		return fmt.Errorf("BAD LENGTH")
	}
	gamma, err := parseProbability(args[1])
	if err != nil {
		return err
	}
	if equal(gamma, one()) {
		return fmt.Errorf("BAD DISCOUNT")
	}
	rewards := []Rat{}
	for _, text := range args[2:] {
		rewards = append(rewards, rat(int64(parseInt(text))))
	}
	matrix := [][]Rat{}
	for i := 0; i < c.size(); i++ {
		row := []Rat{}
		for j := 0; j < c.size(); j++ {
			row = append(row, sub(delta(i, j), mul(gamma, c.matrix[i][j])))
		}
		matrix = append(matrix, append(row, rewards[i]))
	}
	solution := eliminate(matrix, c.size())
	values := []Rat{}
	for _, row := range solution {
		values = append(values, row[0])
	}
	d := decompose(c)
	gains := make([]Rat, c.size())
	for i := range gains {
		gains[i] = zero()
	}
	for _, item := range d.closedClasses() {
		distribution := stationaryDistribution(c, item.members)
		gain := zero()
		for index, i := range item.members {
			gain = add(gain, mul(distribution[index], rewards[i]))
		}
		targets := membership(c.size(), item.members)
		probabilities := hittingProbabilities(c, d, targets)
		for i := range gains {
			gains[i] = add(gains[i], mul(probabilities[i], gain))
		}
	}
	a.emit("REWARD", args[0], "gamma="+fractionText(gamma))
	for i, name := range c.names {
		a.emit("VALUE", name, "discounted="+valueText(values[i]), "gain="+valueText(gains[i]))
	}
	return nil
}

func (a *Analyzer) cmdRestrict(args []string) error {
	c, err := a.stochastic(args[0])
	if err != nil {
		return err
	}
	states, err := c.distinctStates(args[2:])
	if err != nil {
		return err
	}
	inside := membership(c.size(), states)
	for i := 0; i < c.size(); i++ {
		if inside[i] {
			for j := 0; j < c.size(); j++ {
				if c.edge(i, j) && !inside[j] {
					return fmt.Errorf("NOT CLOSED %s", c.names[i])
				}
			}
		}
	}
	members := []int{}
	for i, present := range inside {
		if present {
			members = append(members, i)
		}
	}
	restricted := newChain(c.labels(members))
	for r, i := range members {
		for col, j := range members {
			restricted.matrix[r][col] = c.matrix[i][j]
		}
	}
	a.chains[args[1]] = restricted
	a.emit("RESTRICT", args[0], args[1], fmt.Sprintf("states=%d", len(members)))
	a.display(restricted.names, restricted.matrix, "ROW")
	return nil
}

func lcmBig(a, b *big.Int) *big.Int {
	g := new(big.Int).GCD(nil, nil, a, b)
	ratio := new(big.Int).Quo(a, g)
	return ratio.Mul(ratio, b)
}

func (a *Analyzer) cmdSimulate(args []string) error {
	c, err := a.stochastic(args[0])
	if err != nil {
		return err
	}
	start, err := c.state(args[1])
	if err != nil {
		return err
	}
	steps, seed := parseInt(args[2]), int64(parseInt(args[3]))
	if steps == 0 {
		return fmt.Errorf("BAD STEPS")
	}
	if seed <= 0 || seed >= modulus {
		return fmt.Errorf("BAD SEED")
	}
	randomValue := seed
	path := []int{start}
	for t := 0; t < steps; t++ {
		row := c.matrix[path[len(path)-1]]
		common := big.NewInt(1)
		for _, value := range row {
			common = lcmBig(common, value.Denom())
		}
		randomValue = multiplier * randomValue % modulus
		threshold := new(big.Int).Mod(big.NewInt(randomValue), common)
		thresholdRat := new(big.Rat).SetInt(threshold)
		commonRat := new(big.Rat).SetInt(common)
		cumulative := zero()
		for j, value := range row {
			cumulative = add(cumulative, value)
			if mul(cumulative, commonRat).Cmp(thresholdRat) > 0 {
				path = append(path, j)
				break
			}
		}
	}
	a.emit("SIMULATE", args[0], args[1], fmt.Sprintf("steps=%d", steps),
		fmt.Sprintf("seed=%d", seed), "end="+c.names[path[len(path)-1]])
	parts := []any{"PATH"}
	for _, name := range c.labels(path) {
		parts = append(parts, name)
	}
	a.emit(parts...)
	for i, name := range c.names {
		count := 0
		for _, state := range path {
			if state == i {
				count++
			}
		}
		a.emit("VISIT", name, count)
	}
	return nil
}

func (a *Analyzer) execute(line string) {
	parts := strings.Split(line, " ")
	command, args := parts[0], parts[1:]
	var err error
	switch command {
	case "CHAIN":
		err = a.cmdChain(args)
	case "P":
		err = a.cmdP(args)
	case "ROW":
		err = a.cmdRow(args)
	case "SHOW":
		err = a.cmdShow(args)
	case "CHECK":
		err = a.cmdCheck(args)
	case "BUILD":
		err = a.cmdBuild(args)
	case "GAMBLER":
		err = a.cmdGambler(args)
	case "CLASSES":
		err = a.cmdClasses(args)
	case "CLASSIFY":
		err = a.cmdClassify(args)
	case "STEP":
		err = a.cmdStep(args)
	case "POWER":
		err = a.cmdPower(args)
	case "STATIONARY":
		err = a.cmdStationary(args)
	case "RECURRENCE":
		err = a.cmdRecurrence(args)
	case "ABSORB":
		err = a.cmdAbsorb(args)
	case "HITTING":
		err = a.cmdHitting(args)
	case "PASSAGE":
		err = a.cmdPassage(args)
	case "FIRSTPASSAGE":
		err = a.cmdFirstPassage(args)
	case "PATHPROB":
		err = a.cmdPathProb(args)
	case "MOSTLIKELY":
		err = a.cmdMostLikely(args)
	case "REVERSIBLE":
		err = a.cmdReversible(args)
	case "REVERSE":
		err = a.cmdReverse(args)
	case "MIXING":
		err = a.cmdMixing(args)
	case "LUMP":
		err = a.cmdLump(args)
	case "REWARD":
		err = a.cmdReward(args)
	case "RESTRICT":
		err = a.cmdRestrict(args)
	case "SIMULATE":
		err = a.cmdSimulate(args)
	}
	if err != nil {
		a.emit("ERROR", err.Error())
	}
}

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 4096), 1<<20)
	scanner.Scan()
	count := parseInt(scanner.Text())
	analyzer := newAnalyzer()
	for i := 0; i < count && scanner.Scan(); i++ {
		analyzer.execute(scanner.Text())
	}
	writer := bufio.NewWriter(os.Stdout)
	defer writer.Flush()
	fmt.Fprintln(writer, strings.Join(analyzer.output, "\n"))
}
