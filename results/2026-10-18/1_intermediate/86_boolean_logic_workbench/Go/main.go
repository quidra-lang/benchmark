package main

import (
	"bufio"
	"fmt"
	"math/bits"
	"os"
	"sort"
	"strconv"
	"strings"
)

type node struct {
	kind        string
	left, right *node
}

func leaf(kind string) *node                      { return &node{kind: kind} }
func unary(child *node) *node                     { return &node{kind: "~", left: child} }
func binary(kind string, left, right *node) *node { return &node{kind: kind, left: left, right: right} }
func precedence(kind string) int {
	switch kind {
	case "<->":
		return 1
	case "->":
		return 2
	case "|":
		return 3
	case "^":
		return 4
	case "&":
		return 5
	}
	return 0
}
func notation(n *node) string {
	if n.left == nil {
		return n.kind
	}
	if n.kind == "~" {
		child := notation(n.left)
		if precedence(n.left.kind) > 0 {
			child = "(" + child + ")"
		}
		return "~" + child
	}
	left, right := notation(n.left), notation(n.right)
	if p := precedence(n.left.kind); p > 0 && (p < precedence(n.kind) || n.kind == "->" && n.left.kind == "->") {
		left = "(" + left + ")"
	}
	if p := precedence(n.right.kind); p > 0 && (p < precedence(n.kind) || n.kind == n.right.kind && n.kind != "->") {
		right = "(" + right + ")"
	}
	return left + " " + n.kind + " " + right
}
func equal(a, b *node) bool {
	return a == b || a.kind == b.kind && (a.left == nil || equal(a.left, b.left) && (a.right == nil || equal(a.right, b.right)))
}
func variable(kind string) bool { return len(kind) == 1 && kind[0] >= 'A' && kind[0] <= 'Z' }
func validName(name string) bool {
	if name == "" || len(name) > 8 || name[0] < 'a' || name[0] > 'z' {
		return false
	}
	for i := range name {
		if !(name[i] >= 'a' && name[i] <= 'z' || name[i] >= '0' && name[i] <= '9') {
			return false
		}
	}
	return true
}

type problem string

func fail(format string, args ...any) { panic(problem(fmt.Sprintf(format, args...))) }
func contains(items []string, text string) bool {
	for _, item := range items {
		if item == text {
			return true
		}
	}
	return false
}

type token struct {
	text     string
	position int
}
type parser struct {
	tokens  []token
	at, end int
	names   map[string]*node
}

func lexical(text string, start int) []token {
	tokens := []token{}
	for i := 0; i < len(text); {
		if text[i] == ' ' {
			i++
			continue
		}
		begin := i
		switch {
		case strings.HasPrefix(text[i:], "<->"):
			i += 3
		case strings.HasPrefix(text[i:], "->"):
			i += 2
		case text[i] >= 'a' && text[i] <= 'z':
			for i < len(text) && (text[i] >= 'a' && text[i] <= 'z' || text[i] >= '0' && text[i] <= '9') {
				i++
			}
		case strings.ContainsRune("ABCDEFGHIJKLMNOPQRSTUVWXYZ01~&^|()", rune(text[i])):
			i++
		default:
			fail("invalid character '%c' at %d", text[i], start+i)
		}
		tokens = append(tokens, token{text[begin:i], start + begin})
	}
	return tokens
}
func (p *parser) unexpected() {
	if p.at == len(p.tokens) {
		fail("unexpected end of formula at %d", p.end)
	}
	t := p.tokens[p.at]
	fail("unexpected '%s' at %d", t.text, t.position)
}
func (p *parser) unary() *node {
	if p.at == len(p.tokens) {
		p.unexpected()
	}
	t := p.tokens[p.at]
	if t.text == "~" {
		p.at++
		return unary(p.unary())
	}
	if t.text == "(" {
		p.at++
		value := p.expression(1)
		if p.at == len(p.tokens) || p.tokens[p.at].text != ")" {
			p.unexpected()
		}
		p.at++
		return value
	}
	if variable(t.text) || t.text == "0" || t.text == "1" {
		p.at++
		return leaf(t.text)
	}
	if t.text[0] >= 'a' && t.text[0] <= 'z' {
		value := p.names[t.text]
		if value == nil {
			fail("undefined name '%s' at %d", t.text, t.position)
		}
		p.at++
		return value
	}
	p.unexpected()
	return nil
}
func (p *parser) expression(minimum int) *node {
	value := p.unary()
	for p.at < len(p.tokens) {
		operator := p.tokens[p.at].text
		priority := precedence(operator)
		if priority < minimum {
			break
		}
		p.at++
		next := priority + 1
		if operator == "->" {
			next = priority
		}
		value = binary(operator, value, p.expression(next))
	}
	return value
}
func parse(text string, start int, names map[string]*node) *node {
	p := parser{tokens: lexical(text, start), end: start + len(text), names: names}
	value := p.expression(1)
	if p.at != len(p.tokens) {
		p.unexpected()
	}
	return value
}
func variableList(formulas ...*node) []string {
	set := map[string]bool{}
	var walk func(*node)
	walk = func(n *node) {
		if variable(n.kind) {
			set[n.kind] = true
		}
		if n.left != nil {
			walk(n.left)
		}
		if n.right != nil {
			walk(n.right)
		}
	}
	for _, formula := range formulas {
		walk(formula)
	}
	names := []string{}
	for name := range set {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}
func size(n *node) int {
	if n.left == nil {
		return 1
	}
	if n.right == nil {
		return 1 + size(n.left)
	}
	return 1 + size(n.left) + size(n.right)
}
func depth(n *node) int {
	if n.left == nil {
		return 1
	}
	if n.right == nil {
		return 1 + depth(n.left)
	}
	return 1 + max(depth(n.left), depth(n.right))
}
func truth(n *node, assignment map[string]int) int {
	if variable(n.kind) {
		return assignment[n.kind]
	}
	if n.kind == "0" {
		return 0
	}
	if n.kind == "1" {
		return 1
	}
	a := truth(n.left, assignment)
	if n.kind == "~" {
		return 1 - a
	}
	b := truth(n.right, assignment)
	switch n.kind {
	case "&":
		return a & b
	case "|":
		return a | b
	case "^":
		return a ^ b
	case "->":
		return (1 - a) | b
	default:
		return 1 - (a ^ b)
	}
}
func table(n *node, names []string) []int {
	result := make([]int, 1<<len(names))
	for row := range result {
		assignment := map[string]int{}
		for i, name := range names {
			assignment[name] = row >> (len(names) - 1 - i) & 1
		}
		result[row] = truth(n, assignment)
	}
	return result
}
func assignmentText(names []string, row int) string {
	parts := []string{}
	for i, name := range names {
		parts = append(parts, fmt.Sprintf("%s=%d", name, row>>(len(names)-1-i)&1))
	}
	return "{" + strings.Join(parts, " ") + "}"
}
func bitPattern(row, n int) string {
	result := make([]byte, n)
	for i := range result {
		result[i] = byte('0' + (row >> (n - 1 - i) & 1))
	}
	return string(result)
}
func literalCount(pattern string) int { return len(pattern) - strings.Count(pattern, "-") }
func patternCompare(a, b string) int {
	rank := func(c byte) int {
		if c == '1' {
			return 0
		}
		if c == '0' {
			return 1
		}
		return 2
	}
	for i := range a {
		if rank(a[i]) != rank(b[i]) {
			return rank(a[i]) - rank(b[i])
		}
	}
	return 0
}
func sortPatterns(patterns []string) {
	sort.Slice(patterns, func(i, j int) bool { return patternCompare(patterns[i], patterns[j]) < 0 })
}
func flipped(pattern string) string {
	return strings.Map(func(c rune) rune {
		if c == '1' {
			return '0'
		}
		if c == '0' {
			return '1'
		}
		return c
	}, pattern)
}
func termText(pattern string, names []string, clause bool) string {
	literals := []string{}
	for i := range pattern {
		if pattern[i] != '-' {
			text := names[i]
			if pattern[i] == '0' {
				text = "~" + text
			}
			literals = append(literals, text)
		}
	}
	if len(literals) == 0 {
		if clause {
			return "0"
		}
		return "1"
	}
	separator := " & "
	if clause {
		separator = " | "
	}
	return strings.Join(literals, separator)
}
func formText(patterns []string, names []string, clauses bool) string {
	if len(patterns) == 0 {
		if clauses {
			return "1"
		}
		return "0"
	}
	parts := []string{}
	for _, pattern := range patterns {
		text := termText(pattern, names, clauses)
		if clauses && len(patterns) >= 2 && literalCount(pattern) >= 2 {
			text = "(" + text + ")"
		}
		parts = append(parts, text)
	}
	separator := " | "
	if clauses {
		separator = " & "
	}
	return strings.Join(parts, separator)
}
func reduceNegation(n *node) *node {
	if n.kind == "0" {
		return leaf("1")
	}
	if n.kind == "1" {
		return leaf("0")
	}
	if n.kind == "~" {
		return n.left
	}
	return unary(n)
}
func simplifyBinary(operator string, a, b *node) *node {
	same := equal(a, b)
	complement := a.kind == "~" && equal(a.left, b) || b.kind == "~" && equal(b.left, a)
	switch operator {
	case "&":
		if a.kind == "0" || b.kind == "0" {
			return leaf("0")
		}
		if a.kind == "1" {
			return b
		}
		if b.kind == "1" || same {
			return a
		}
		if complement {
			return leaf("0")
		}
	case "|":
		if a.kind == "1" || b.kind == "1" {
			return leaf("1")
		}
		if a.kind == "0" {
			return b
		}
		if b.kind == "0" || same {
			return a
		}
		if complement {
			return leaf("1")
		}
	case "^":
		if a.kind == "0" {
			return b
		}
		if b.kind == "0" {
			return a
		}
		if a.kind == "1" {
			return reduceNegation(b)
		}
		if b.kind == "1" {
			return reduceNegation(a)
		}
		if same {
			return leaf("0")
		}
		if complement {
			return leaf("1")
		}
	case "->":
		if a.kind == "0" || b.kind == "1" {
			return leaf("1")
		}
		if a.kind == "1" {
			return b
		}
		if b.kind == "0" {
			return reduceNegation(a)
		}
		if same {
			return leaf("1")
		}
		if complement {
			return b
		}
	case "<->":
		if a.kind == "1" {
			return b
		}
		if b.kind == "1" {
			return a
		}
		if a.kind == "0" {
			return reduceNegation(b)
		}
		if b.kind == "0" {
			return reduceNegation(a)
		}
		if same {
			return leaf("1")
		}
		if complement {
			return leaf("0")
		}
	}
	return binary(operator, a, b)
}
func simplify(n *node, assignments map[string]string) *node {
	if n.left == nil {
		if value, exists := assignments[n.kind]; exists {
			return leaf(value)
		}
		return n
	}
	a := simplify(n.left, assignments)
	if n.kind == "~" {
		return reduceNegation(a)
	}
	return simplifyBinary(n.kind, a, simplify(n.right, assignments))
}

type signedNode struct {
	node     *node
	positive bool
}

func nnf(n *node, positive bool, memo map[signedNode]*node) *node {
	key := signedNode{n, positive}
	if value := memo[key]; value != nil {
		return value
	}
	var result *node
	switch n.kind {
	case "0", "1":
		result = n
		if !positive {
			result = reduceNegation(n)
		}
	case "~":
		result = nnf(n.left, !positive, memo)
	case "&", "|":
		operator := n.kind
		if !positive {
			if operator == "&" {
				operator = "|"
			} else {
				operator = "&"
			}
		}
		result = binary(operator, nnf(n.left, positive, memo), nnf(n.right, positive, memo))
	case "->":
		operator := "|"
		if !positive {
			operator = "&"
		}
		result = binary(operator, nnf(n.left, !positive, memo), nnf(n.right, positive, memo))
	case "^", "<->":
		sign := positive
		if n.kind == "^" {
			sign = !sign
		}
		left := binary("&", nnf(n.left, true, memo), nnf(n.right, sign, memo))
		right := binary("&", nnf(n.left, false, memo), nnf(n.right, !sign, memo))
		result = binary("|", left, right)
	default:
		result = n
		if !positive {
			result = unary(n)
		}
	}
	memo[key] = result
	return result
}
func dual(n *node) *node {
	if variable(n.kind) {
		return n
	}
	if n.kind == "0" || n.kind == "1" {
		return reduceNegation(n)
	}
	if n.kind == "~" {
		return unary(dual(n.left))
	}
	a, b := dual(n.left), dual(n.right)
	switch n.kind {
	case "&":
		return binary("|", a, b)
	case "|":
		return binary("&", a, b)
	case "^":
		return binary("<->", a, b)
	case "<->":
		return binary("^", a, b)
	default:
		return binary("&", unary(a), b)
	}
}
func covers(pattern string, row int) bool {
	bits := bitPattern(row, len(pattern))
	for i := range pattern {
		if pattern[i] != '-' && pattern[i] != bits[i] {
			return false
		}
	}
	return true
}
func patternSubset(a, b string) bool {
	for i := range a {
		if a[i] != '-' && a[i] != b[i] {
			return false
		}
	}
	return true
}
func tidy(patterns []string) []string {
	unique := []string{}
	for _, pattern := range patterns {
		if !contains(unique, pattern) {
			unique = append(unique, pattern)
		}
	}
	result := []string{}
	for i, pattern := range unique {
		redundant := false
		for j, other := range unique {
			if i != j && patternSubset(other, pattern) {
				redundant = true
				break
			}
		}
		if !redundant {
			result = append(result, pattern)
		}
	}
	return result
}
func mergeClauses(a, b string) (string, bool) {
	result := []byte(a)
	for i := range b {
		if b[i] == '-' {
			continue
		}
		if result[i] != '-' && result[i] != b[i] {
			return "", false
		}
		result[i] = b[i]
	}
	return string(result), true
}
func clauses(n *node, names []string, memo map[*node][]string) []string {
	if result, exists := memo[n]; exists {
		return result
	}
	empty := strings.Repeat("-", len(names))
	var result []string
	switch n.kind {
	case "1":
		result = []string{}
	case "0":
		result = []string{empty}
	case "&":
		result = tidy(append(append([]string(nil), clauses(n.left, names, memo)...), clauses(n.right, names, memo)...))
	case "|":
		result = []string{}
		for _, a := range clauses(n.left, names, memo) {
			for _, b := range clauses(n.right, names, memo) {
				if merged, ok := mergeClauses(a, b); ok {
					result = append(result, merged)
				}
			}
		}
		result = tidy(result)
	default:
		name, sign := n.kind, byte('1')
		if n.kind == "~" {
			name, sign = n.left.kind, '0'
		}
		pattern := []byte(empty)
		for i, variable := range names {
			if variable == name {
				pattern[i] = sign
			}
		}
		result = []string{string(pattern)}
	}
	memo[n] = result
	return result
}
func minimize(values, dc []int, names []string, pos bool) []string {
	on, stage := []int{}, []string{}
	for row, value := range values {
		if value == 1 && (dc == nil || dc[row] == 0) {
			on = append(on, row)
		}
		if value == 1 || dc != nil && dc[row] == 1 {
			stage = append(stage, bitPattern(row, len(names)))
		}
	}
	out, primes := []string{}, []string{}
	for level := 0; ; level++ {
		used, next := map[string]bool{}, []string{}
		for i, a := range stage {
			for _, b := range stage[i+1:] {
				differing := -1
				for j := range a {
					if a[j] != b[j] {
						if a[j] == '-' || b[j] == '-' || differing >= 0 {
							differing = -2
							break
						}
						differing = j
					}
				}
				if differing >= 0 {
					pattern := []byte(a)
					pattern[differing] = '-'
					combined := string(pattern)
					used[a], used[b] = true, true
					if !contains(next, combined) {
						next = append(next, combined)
					}
				}
			}
		}
		count := 0
		for _, pattern := range stage {
			if !used[pattern] {
				primes = append(primes, pattern)
				count++
			}
		}
		if !pos {
			out = append(out, fmt.Sprintf("stage %d: implicants %d primes %d", level, len(stage), count))
		}
		if len(next) == 0 {
			break
		}
		stage = next
	}
	target := []string{}
	for _, pattern := range primes {
		for _, row := range on {
			if covers(pattern, row) {
				target = append(target, pattern)
				break
			}
		}
	}
	sortPatterns(target)
	essential := []string{}
	for _, row := range on {
		options := []string{}
		for _, pattern := range target {
			if covers(pattern, row) {
				options = append(options, pattern)
			}
		}
		if len(options) == 1 && !contains(essential, options[0]) {
			essential = append(essential, options[0])
		}
	}
	sortPatterns(essential)
	optional := []string{}
	for _, pattern := range target {
		if !contains(essential, pattern) {
			optional = append(optional, pattern)
		}
	}
	display := func(cover []string) []string {
		result := append([]string(nil), cover...)
		if pos {
			for i := range result {
				result[i] = flipped(result[i])
			}
		}
		sortPatterns(result)
		return result
	}
	var best []string
	bestCount, bestLiterals := int(^uint(0)>>1), int(^uint(0)>>1)
	for mask := 0; mask < 1<<len(optional); mask++ {
		chosen := append([]string(nil), essential...)
		for i, pattern := range optional {
			if mask>>i&1 != 0 {
				chosen = append(chosen, pattern)
			}
		}
		valid := true
		for _, row := range on {
			found := false
			for _, pattern := range chosen {
				if covers(pattern, row) {
					found = true
					break
				}
			}
			if !found {
				valid = false
				break
			}
		}
		if !valid {
			continue
		}
		literals := 0
		for _, pattern := range chosen {
			literals += literalCount(pattern)
		}
		candidate := display(chosen)
		better := len(chosen) < bestCount || len(chosen) == bestCount && literals < bestLiterals
		if len(chosen) == bestCount && literals == bestLiterals {
			for i := range candidate {
				c := patternCompare(candidate[i], best[i])
				if c != 0 {
					better = c < 0
					break
				}
			}
		}
		if better {
			best, bestCount, bestLiterals = candidate, len(chosen), literals
		}
	}
	if pos {
		return []string{"minimal: " + formText(best, names, true), fmt.Sprintf("clauses %d literals %d", bestCount, bestLiterals)}
	}
	terms := func(patterns []string) string {
		if len(patterns) == 0 {
			return "none"
		}
		parts := []string{}
		for _, pattern := range patterns {
			parts = append(parts, termText(pattern, names, false))
		}
		return strings.Join(parts, ", ")
	}
	return append(out, "primes: "+terms(target), "essential: "+terms(essential), "minimal: "+formText(best, names, false), fmt.Sprintf("terms %d literals %d", bestCount, bestLiterals))
}
func coefficients(values []int, n int) []int {
	result := append([]int(nil), values...)
	for bit := 0; bit < n; bit++ {
		for row := range result {
			if row>>bit&1 != 0 {
				result[row] ^= result[row^(1<<bit)]
			}
		}
	}
	return result
}

type workbench struct{ names map[string]*node }

var commands = strings.Fields("DEF DEFSUM DEL LIST PRINT TABLE MINTERMS MAXTERMS DNF CNF NNF DUAL ANF SIMPLIFY RESTRICT COFACTOR MINIMIZE MINDC MINPOS KMAP SAT TAUT COUNT EQUIV IMPLIES PROPS BDD CLAUSES DP")
var truthCommands = strings.Fields("TABLE MINTERMS MAXTERMS DNF CNF ANF SAT TAUT COUNT EQUIV IMPLIES PROPS KMAP BDD MINIMIZE MINDC MINPOS")

func (w *workbench) command(line string) []string {
	command, argument := line, ""
	separator := strings.IndexByte(line, ' ')
	if separator >= 0 {
		command, argument = line[:separator], line[separator+1:]
	}
	if !contains(commands, command) {
		fail("unknown command %s", command)
	}
	if command == "LIST" {
		if separator >= 0 {
			fail("unexpected argument")
		}
		names := []string{}
		for name := range w.names {
			names = append(names, name)
		}
		sort.Strings(names)
		out := []string{fmt.Sprintf("names: %d", len(names))}
		for _, name := range names {
			out = append(out, name+" = "+notation(w.names[name]))
		}
		return out
	}
	if separator < 0 {
		fail("missing argument")
	}
	if command == "DEF" {
		space := strings.IndexByte(argument, ' ')
		if space < 0 {
			fail("missing argument")
		}
		name := argument[:space]
		if !validName(name) {
			fail("invalid name '%s'", name)
		}
		formula := parse(argument[space+1:], len(name)+6, w.names)
		prefix := "defined"
		if w.names[name] != nil {
			prefix = "redefined"
		}
		w.names[name] = formula
		return []string{prefix + " " + name + " = " + notation(formula)}
	}
	if command == "DEL" {
		if !validName(argument) {
			fail("invalid name '%s'", argument)
		}
		if w.names[argument] == nil {
			fail("undefined name '%s'", argument)
		}
		delete(w.names, argument)
		return []string{"deleted " + argument}
	}
	if command == "DEFSUM" {
		semicolon := strings.IndexByte(argument, ';')
		if semicolon < 0 {
			fail("missing ';'")
		}
		words := strings.Fields(argument[:semicolon])
		if len(words) == 0 {
			fail("missing argument")
		}
		name := words[0]
		if !validName(name) {
			fail("invalid name '%s'", name)
		}
		names := words[1:]
		if len(names) == 0 {
			fail("bad variable list")
		}
		for i, text := range names {
			if !variable(text) || i > 0 && text <= names[i-1] {
				fail("bad variable list")
			}
		}
		if len(names) >= 9 {
			fail("too many variables: %d", len(names))
		}
		previous := -1
		var formula *node
		for _, word := range strings.Fields(argument[semicolon+1:]) {
			valid := word == "0" || word[0] >= '1' && word[0] <= '9'
			for i := range word {
				if word[i] < '0' || word[i] > '9' {
					valid = false
				}
			}
			row, _ := strconv.Atoi(word)
			if !valid || row >= 1<<len(names) || row <= previous {
				fail("bad minterm '%s'", word)
			}
			previous = row
			var product *node
			for i, name := range names {
				literal := leaf(name)
				if row>>(len(names)-1-i)&1 == 0 {
					literal = unary(literal)
				}
				if product == nil {
					product = literal
				} else {
					product = binary("&", product, literal)
				}
			}
			if formula == nil {
				formula = product
			} else {
				formula = binary("|", formula, product)
			}
		}
		if formula == nil {
			formula = leaf("0")
		}
		prefix := "defined"
		if w.names[name] != nil {
			prefix = "redefined"
		}
		w.names[name] = formula
		return []string{prefix + " " + name + " = " + notation(formula)}
	}
	front, back := argument, ""
	start, backStart := len(command)+2, 0
	split := contains([]string{"RESTRICT", "COFACTOR", "MINDC", "EQUIV", "IMPLIES"}, command)
	if split {
		semicolon := strings.IndexByte(argument, ';')
		if semicolon < 0 {
			fail("missing ';'")
		}
		front, back, backStart = argument[:semicolon], argument[semicolon+1:], start+semicolon+1
	}
	formula := parse(front, start, w.names)
	var second *node
	if command == "MINDC" || command == "EQUIV" || command == "IMPLIES" {
		second = parse(back, backStart, w.names)
	}
	if command == "RESTRICT" {
		words := strings.Fields(back)
		if len(words) == 0 {
			fail("missing assignment")
		}
		assignments := map[string]string{}
		for _, word := range words {
			if len(word) != 3 || !variable(word[:1]) || word[1] != '=' || word[2] != '0' && word[2] != '1' {
				fail("bad assignment '%s'", word)
			}
			name := word[:1]
			if _, exists := assignments[name]; exists {
				fail("duplicate variable %s", name)
			}
			assignments[name] = word[2:]
		}
		return []string{"restricted: " + notation(simplify(formula, assignments))}
	}
	if command == "COFACTOR" {
		words := strings.Fields(back)
		if len(words) != 1 || !variable(words[0]) {
			fail("bad variable")
		}
		name := words[0]
		one, zero := simplify(formula, map[string]string{name: "1"}), simplify(formula, map[string]string{name: "0"})
		return []string{"cofactor " + name + "=1: " + notation(one), "cofactor " + name + "=0: " + notation(zero), "difference: " + notation(simplifyBinary("^", one, zero))}
	}
	names := variableList(formula)
	if second != nil {
		names = variableList(formula, second)
	}
	if contains(truthCommands, command) && len(names) >= 9 {
		fail("too many variables: %d", len(names))
	}
	switch command {
	case "PRINT":
		variables := strings.Join(names, " ")
		if len(names) == 0 {
			variables = "none"
		}
		return []string{"formula: " + notation(formula), "variables: " + variables, fmt.Sprintf("size %d depth %d", size(formula), depth(formula))}
	case "SIMPLIFY":
		return []string{"simplified: " + notation(simplify(formula, nil))}
	case "NNF":
		return []string{"nnf: " + notation(nnf(formula, true, map[signedNode]*node{}))}
	case "DUAL":
		return []string{"dual: " + notation(dual(formula))}
	case "CLAUSES", "DP":
		set := clauses(nnf(formula, true, map[signedNode]*node{}), names, map[*node][]string{})
		sortPatterns(set)
		if command == "CLAUSES" {
			return []string{"clauses: " + formText(set, names, true)}
		}
		out := []string{fmt.Sprintf("start: clauses %d", len(set))}
		empty := strings.Repeat("-", len(names))
		for i, name := range names {
			if len(set) == 0 || contains(set, empty) {
				break
			}
			p, q, rest := []string{}, []string{}, []string{}
			for _, pattern := range set {
				switch pattern[i] {
				case '1':
					p = append(p, pattern)
				case '0':
					q = append(q, pattern)
				default:
					rest = append(rest, pattern)
				}
			}
			resolvents := []string{}
			for _, a := range p {
				for _, b := range q {
					x, y := []byte(a), []byte(b)
					x[i], y[i] = '-', '-'
					if merged, ok := mergeClauses(string(x), string(y)); ok && !contains(resolvents, merged) {
						resolvents = append(resolvents, merged)
					}
				}
			}
			set = tidy(append(rest, resolvents...))
			out = append(out, fmt.Sprintf("eliminate %s: resolvents %d clauses %d", name, len(resolvents), len(set)))
		}
		verdict := "satisfiable"
		if contains(set, empty) {
			verdict = "unsatisfiable"
		}
		return append(out, "result: "+verdict)
	}
	values := table(formula, names)
	models, falseRows := []int{}, []int{}
	for row, value := range values {
		if value == 1 {
			models = append(models, row)
		} else {
			falseRows = append(falseRows, row)
		}
	}
	rowPatterns := func(rows []int, flip bool) []string {
		result := []string{}
		for _, row := range rows {
			pattern := bitPattern(row, len(names))
			if flip {
				pattern = flipped(pattern)
			}
			result = append(result, pattern)
		}
		return result
	}
	switch command {
	case "TABLE":
		header := "| F"
		if len(names) > 0 {
			header = strings.Join(names, " ") + " " + header
		}
		out := []string{header}
		for row, value := range values {
			columns := []string{}
			for _, c := range bitPattern(row, len(names)) {
				columns = append(columns, string(c))
			}
			columns = append(columns, "|", strconv.Itoa(value))
			out = append(out, strings.Join(columns, " "))
		}
		return out
	case "MINTERMS", "MAXTERMS":
		rows := models
		if command == "MAXTERMS" {
			rows = falseRows
		}
		parts := []string{}
		for _, row := range rows {
			parts = append(parts, strconv.Itoa(row))
		}
		text := "none"
		if len(parts) > 0 {
			text = strings.Join(parts, " ")
		}
		return []string{strings.ToLower(command) + ": " + text}
	case "DNF":
		return []string{"dnf: " + formText(rowPatterns(models, false), names, false)}
	case "CNF":
		return []string{"cnf: " + formText(rowPatterns(falseRows, true), names, true)}
	case "ANF":
		patterns := []string{}
		for row, coefficient := range coefficients(values, len(names)) {
			if coefficient == 1 {
				patterns = append(patterns, strings.ReplaceAll(bitPattern(row, len(names)), "0", "-"))
			}
		}
		sort.Slice(patterns, func(i, j int) bool {
			a, b := literalCount(patterns[i]), literalCount(patterns[j])
			return a < b || a == b && patternCompare(patterns[i], patterns[j]) < 0
		})
		parts := []string{}
		for _, pattern := range patterns {
			parts = append(parts, termText(pattern, names, false))
		}
		text := "0"
		if len(parts) > 0 {
			text = strings.Join(parts, " ^ ")
		}
		return []string{"anf: " + text}
	case "SAT":
		if len(models) == 0 {
			return []string{"unsatisfiable"}
		}
		return []string{"satisfiable: " + assignmentText(names, models[0])}
	case "TAUT":
		if len(falseRows) == 0 {
			return []string{"tautology"}
		}
		return []string{"not a tautology: " + assignmentText(names, falseRows[0])}
	case "COUNT":
		return []string{fmt.Sprintf("models: %d of %d", len(models), len(values))}
	case "EQUIV", "IMPLIES":
		others := table(second, names)
		for row, value := range values {
			if command == "EQUIV" && value != others[row] {
				return []string{fmt.Sprintf("not equivalent: %s f=%d g=%d", assignmentText(names, row), value, others[row])}
			}
			if command == "IMPLIES" && value == 1 && others[row] == 0 {
				return []string{"does not imply: " + assignmentText(names, row)}
			}
		}
		if command == "EQUIV" {
			return []string{"equivalent"}
		}
		return []string{"implies"}
	case "MINIMIZE":
		return minimize(values, nil, names, false)
	case "MINDC":
		return minimize(values, table(second, names), names, false)
	case "MINPOS":
		inverted := make([]int, len(values))
		for i, value := range values {
			inverted[i] = 1 - value
		}
		return minimize(inverted, nil, names, true)
	case "KMAP":
		n := len(names)
		if n < 2 || n > 4 {
			fail("kmap needs 2 to 4 variables")
		}
		p, q := n/2, n-n/2
		label := strings.Join(names[:p], "") + "\\" + strings.Join(names[p:], "")
		header := label
		for i := 0; i < 1<<q; i++ {
			header += " " + bitPattern(i^(i/2), q)
		}
		out := []string{header}
		for i := 0; i < 1<<p; i++ {
			row := i ^ (i / 2)
			text := bitPattern(row, p) + strings.Repeat(" ", n+1-p)
			for j := 0; j < 1<<q; j++ {
				text += strings.Repeat(" ", q) + strconv.Itoa(values[row<<q|j^(j/2)])
			}
			out = append(out, text)
		}
		return out
	case "PROPS":
		depends := []string{}
		selfDual, monotone, linear, symmetric := true, true, true, true
		weights := map[int]int{}
		for i, name := range names {
			bit := 1 << (len(names) - 1 - i)
			for row, value := range values {
				if value != values[row^bit] {
					depends = append(depends, name)
					break
				}
			}
		}
		for row, value := range values {
			if value == values[len(values)-1-row] {
				selfDual = false
			}
			for i := range names {
				bit := 1 << i
				if row&bit == 0 && value > values[row|bit] {
					monotone = false
				}
			}
			weight := bits.OnesCount(uint(row))
			if previous, exists := weights[weight]; exists && previous != value {
				symmetric = false
			}
			weights[weight] = value
		}
		for row, coefficient := range coefficients(values, len(names)) {
			if coefficient == 1 && bits.OnesCount(uint(row)) > 1 {
				linear = false
			}
		}
		text := strings.Join(depends, " ")
		if len(depends) == 0 {
			text = "none"
		}
		yes := func(value bool) string {
			if value {
				return "yes"
			}
			return "no"
		}
		return []string{"depends: " + text, "zero-preserving: " + yes(values[0] == 0), "one-preserving: " + yes(values[len(values)-1] == 1), "self-dual: " + yes(selfDual), "monotone: " + yes(monotone), "linear: " + yes(linear), "symmetric: " + yes(symmetric)}
	case "BDD":
		type decision struct{ variable, low, high int }
		nodes := []decision{}
		unique := map[decision]int{}
		var build func(int, []int) int
		build = func(level int, rows []int) int {
			if level == len(names) {
				return rows[0]
			}
			low := build(level+1, rows[:len(rows)/2])
			high := build(level+1, rows[len(rows)/2:])
			if low == high {
				return low
			}
			key := decision{level, low, high}
			if index, exists := unique[key]; exists {
				return index
			}
			index := len(nodes) + 2
			nodes = append(nodes, key)
			unique[key] = index
			return index
		}
		root := build(0, values)
		paths := []int{0, 1}
		out := []string{fmt.Sprintf("nodes: %d", len(nodes))}
		for i, n := range nodes {
			out = append(out, fmt.Sprintf("%d = ite(%s, %d, %d)", i+2, names[n.variable], n.high, n.low))
			paths = append(paths, paths[n.low]+paths[n.high])
		}
		return append(out, fmt.Sprintf("root: %d", root), fmt.Sprintf("paths: %d", paths[root]))
	}
	return nil
}
func (w *workbench) process(line string, out *bufio.Writer) {
	defer func() {
		if caught := recover(); caught != nil {
			if reason, ok := caught.(problem); ok {
				fmt.Fprintf(out, "error: %s\n", reason)
			} else {
				panic(caught)
			}
		}
	}()
	for _, text := range w.command(line) {
		fmt.Fprintln(out, text)
	}
}
func main() {
	scanner := bufio.NewScanner(os.Stdin)
	out := bufio.NewWriter(os.Stdout)
	defer out.Flush()
	scanner.Scan()
	count, _ := strconv.Atoi(scanner.Text())
	w := workbench{names: map[string]*node{}}
	for i := 0; i < count && scanner.Scan(); i++ {
		w.process(scanner.Text(), out)
	}
}
