package main

import (
	"fmt"
	"os"
	"slices"
	"sort"
	"strconv"
	"strings"
)

func reachable(g Grammar) StringSet {
	seen := StringSet{g.Start: true}
	queue := []string{g.Start}
	for i := 0; i < len(queue); i++ {
		for _, rhs := range g.Rules[queue[i]] {
			for _, s := range rhs {
				if isNonterminal(s) && !seen[s] {
					seen[s] = true
					queue = append(queue, s)
				}
			}
		}
	}
	return seen
}
func pruneOrder(g *Grammar, keep StringSet) {
	order := []string{}
	for _, lhs := range g.Order {
		if keep[lhs] {
			order = append(order, lhs)
		} else {
			delete(g.Rules, lhs)
		}
	}
	g.Order = order
}
func checkDeclarations(source Grammar) []string {
	out := []string{}
	if source.HasDeclaration {
		set := StringSet{}
		for word := range source.Words {
			if !source.Declared[word] {
				set[word] = true
			}
		}
		for _, word := range terminalOrder(set) {
			out = append(out, fmt.Sprintf("undeclared terminal %s at line %d", word, source.Words[word]))
		}
	}
	return out
}
func cleanGrammar(source Grammar) (Grammar, []string) {
	g := cloneGrammar(source)
	log := []string{}
	defined, undefined := StringSet{}, StringSet{}
	for _, lhs := range g.Order {
		defined[lhs] = true
	}
	for _, lhs := range g.Order {
		for _, rhs := range g.Rules[lhs] {
			for _, s := range rhs {
				if isNonterminal(s) && !defined[s] {
					undefined[s] = true
				}
			}
		}
	}
	names := []string{}
	for name := range undefined {
		names = append(names, name)
	}
	sort.Slice(names, func(i, j int) bool { return names[i][1:len(names[i])-1] < names[j][1:len(names[j])-1] })
	for _, name := range names {
		log = append(log, "undefined nonterminal "+name)
	}
	removeAlternatives := func(discarded StringSet, kind string) {
		for _, lhs := range g.Order {
			kept := [][]string{}
			for _, rhs := range g.Rules[lhs] {
				bad := ""
				for _, s := range rhs {
					if discarded[s] {
						bad = s
						break
					}
				}
				if bad != "" {
					log = append(log, "removed "+productionNotation(lhs, rhs)+" ("+kind+" "+bad+")")
				} else {
					kept = append(kept, rhs)
				}
			}
			g.Rules[lhs] = kept
		}
	}
	removeAlternatives(undefined, "undefined")
	productive := StringSet{}
	for {
		changed := false
		for _, lhs := range g.Order {
			if productive[lhs] {
				continue
			}
			for _, rhs := range g.Rules[lhs] {
				good := true
				for _, s := range rhs {
					if isNonterminal(s) && !productive[s] {
						good = false
						break
					}
				}
				if good {
					productive[lhs] = true
					changed = true
					break
				}
			}
		}
		if !changed {
			break
		}
	}
	discarded := StringSet{}
	for _, lhs := range g.Order {
		if !productive[lhs] {
			log = append(log, "unproductive nonterminal "+lhs)
			discarded[lhs] = true
		}
	}
	pruneOrder(&g, productive)
	removeAlternatives(discarded, "unproductive")
	reached := reachable(g)
	for _, lhs := range g.Order {
		if !reached[lhs] {
			log = append(log, "unreachable nonterminal "+lhs)
		}
	}
	pruneOrder(&g, reached)
	return g, log
}
func recursionDiagnostics(g Grammar) []string {
	log := []string{}
	for _, start := range g.Order {
		queue := []string{start}
		parent := map[string]string{start: ""}
		found := false
		for cursor := 0; cursor < len(queue) && !found; cursor++ {
			lhs := queue[cursor]
			for _, rhs := range g.Rules[lhs] {
				if len(rhs) == 0 || !isNonterminal(rhs[0]) {
					continue
				}
				next := rhs[0]
				if next == start {
					path := []string{lhs}
					for parent[path[len(path)-1]] != "" {
						path = append(path, parent[path[len(path)-1]])
					}
					slices.Reverse(path)
					path = append(path, start)
					log = append(log, "left recursion: "+strings.Join(path, " -> "))
					found = true
					break
				}
				if _, ok := parent[next]; !ok {
					parent[next] = lhs
					queue = append(queue, next)
				}
			}
		}
	}
	return log
}
func finalPruning(grammar Grammar) (Grammar, []string, []string) {
	g := cloneGrammar(grammar)
	reached := reachable(g)
	log, diags := []string{}, []string{}
	for _, lhs := range g.Order {
		if !reached[lhs] {
			log = append(log, "remove unreachable "+lhs)
			diags = append(diags, "unreachable after transformation "+lhs)
		}
	}
	pruneOrder(&g, reached)
	return g, log, diags
}
func unusedDeclarations(source, g Grammar) []string {
	out := []string{}
	if source.HasDeclaration {
		known := terminalsOf(g)
		unused := StringSet{}
		for t := range source.Declared {
			if !known[t] {
				unused[t] = true
			}
		}
		for _, t := range terminalOrder(unused) {
			out = append(out, "unused token "+t)
		}
	}
	return out
}
func grammarSummary(g Grammar) string {
	count, empty, unit := 0, 0, 0
	for _, lhs := range g.Order {
		for _, rhs := range g.Rules[lhs] {
			count++
			if len(rhs) == 0 {
				empty++
			}
			if len(rhs) == 1 && isNonterminal(rhs[0]) {
				unit++
			}
		}
	}
	return fmt.Sprintf("start=%s nonterminals=%d terminals=%d productions=%d empty=%d unit=%d", g.Start, len(g.Order), len(terminalsOf(g)), count, empty, unit)
}
func grammarListing(g Grammar, numbered bool) []string {
	out := []string{}
	width := len(strconv.Itoa(len(numberProductions(g))))
	number := 0
	for _, lhs := range g.Order {
		for i, rhs := range g.Rules[lhs] {
			number++
			line := productionNotation(lhs, rhs)
			if i > 0 {
				line = strings.Repeat(" ", len(lhs)) + " | " + notation(rhs)
			}
			if numbered {
				line = fmt.Sprintf("%*d  %s", width, number, line)
			}
			out = append(out, line)
		}
	}
	return out
}
func intStrings(values []int) []string {
	out := make([]string, len(values))
	for i, v := range values {
		out[i] = strconv.Itoa(v)
	}
	return out
}
func listLine(heading string, items []string) string {
	if len(items) == 0 {
		return heading
	}
	return heading + " " + strings.Join(items, " ")
}
func grammarFile(cleaned, recursion, factored, final Grammar, firstLog, secondLog, lastLog []string) []string {
	lines := append([]string{"== cleaned grammar ==", grammarSummary(cleaned)}, grammarListing(cleaned, false)...)
	stages := []struct {
		Title    string
		Grammar  Grammar
		Log      []string
		Numbered bool
	}{{"left recursion elimination", recursion, firstLog, false}, {"left factoring", factored, secondLog, false}, {"final grammar", final, lastLog, true}}
	for _, stage := range stages {
		lines = append(lines, "", "== "+stage.Title+" ==")
		if len(stage.Log) == 0 {
			lines = append(lines, "none")
		} else {
			lines = append(lines, stage.Log...)
		}
		lines = append(lines, grammarSummary(stage.Grammar))
		lines = append(lines, grammarListing(stage.Grammar, stage.Numbered)...)
	}
	lines = append(lines, "", "== cross reference ==")
	productions := numberProductions(final)
	for _, symbol := range concatenate(final.Order, terminalOrder(terminalsOf(final))) {
		numbers := []int{}
		for _, p := range productions {
			if slices.Contains(p.RHS, symbol) {
				numbers = append(numbers, p.Number)
			}
		}
		name := symbol
		if !isNonterminal(symbol) {
			name = "\"" + symbol + "\""
		}
		if len(numbers) == 0 {
			lines = append(lines, name+" not used")
		} else {
			lines = append(lines, listLine(name+" used in", intStrings(numbers)))
		}
	}
	return lines
}

type Measure struct{ Length, Height int }

func measureLess(a, b Measure) bool {
	return a.Length < b.Length || a.Length == b.Length && a.Height < b.Height
}
func sequenceMeasure(rhs []string, scores map[string]Measure) (Measure, bool) {
	out := Measure{Height: 1}
	for _, s := range rhs {
		if isNonterminal(s) {
			v, ok := scores[s]
			if !ok {
				return Measure{}, false
			}
			out.Length += v.Length
			out.Height = max(out.Height, v.Height+1)
		} else {
			out.Length++
		}
	}
	return out, true
}
func expandSequence(rhs []string, sentences map[string][]string) []string {
	out := []string{}
	for _, s := range rhs {
		if isNonterminal(s) {
			out = append(out, sentences[s]...)
		} else {
			out = append(out, s)
		}
	}
	return out
}
func shortestSentences(g Grammar) (map[string]Measure, map[string][]string) {
	scores := map[string]Measure{}
	for {
		changed := false
		for _, lhs := range g.Order {
			for _, rhs := range g.Rules[lhs] {
				candidate, valid := sequenceMeasure(rhs, scores)
				old, known := scores[lhs]
				if valid && (!known || measureLess(candidate, old)) {
					scores[lhs] = candidate
					changed = true
				}
			}
		}
		if !changed {
			break
		}
	}
	selected := map[string][]string{}
	for _, lhs := range g.Order {
		for _, rhs := range g.Rules[lhs] {
			measure, valid := sequenceMeasure(rhs, scores)
			if valid && measure == scores[lhs] {
				selected[lhs] = rhs
				break
			}
		}
	}
	sentences := map[string][]string{}
	var expand func(string) []string
	expand = func(symbol string) []string {
		if !isNonterminal(symbol) {
			return []string{symbol}
		}
		if v, ok := sentences[symbol]; ok {
			return v
		}
		out := []string{}
		for _, s := range selected[symbol] {
			out = append(out, expand(s)...)
		}
		sentences[symbol] = out
		return out
	}
	for _, lhs := range g.Order {
		expand(lhs)
	}
	return scores, sentences
}

type Context struct{ Prefix, Suffix []string }
type ContextParent struct {
	Number, Index int
	LHS           string
	Before, After []string
}

func shortestContexts(g Grammar, scores map[string]Measure, sentences map[string][]string) map[string]Context {
	productions := numberProductions(g)
	costs := map[string]Measure{g.Start: {}}
	parents := map[string]ContextParent{}
	for {
		changed := false
		for _, p := range productions {
			outer, known := costs[p.LHS]
			if !known {
				continue
			}
			for i, s := range p.RHS {
				if !isNonterminal(s) || s == g.Start {
					continue
				}
				before, after := p.RHS[:i], p.RHS[i+1:]
				length := 0
				for _, other := range concatenate(before, after) {
					if isNonterminal(other) {
						length += scores[other].Length
					} else {
						length++
					}
				}
				candidate := Measure{outer.Length + length, outer.Height + 1}
				old, exists := costs[s]
				parent := parents[s]
				tieBetter := candidate == old && (p.Number < parent.Number || p.Number == parent.Number && i < parent.Index)
				if !exists || measureLess(candidate, old) || tieBetter {
					costs[s] = candidate
					parents[s] = ContextParent{p.Number, i, p.LHS, before, after}
					changed = true
				}
			}
		}
		if !changed {
			break
		}
	}
	memo := map[string]Context{g.Start: {}}
	var context func(string) Context
	context = func(symbol string) Context {
		if v, ok := memo[symbol]; ok {
			return v
		}
		p := parents[symbol]
		outer := context(p.LHS)
		v := Context{concatenate(outer.Prefix, expandSequence(p.Before, sentences)), concatenate(expandSequence(p.After, sentences), outer.Suffix)}
		memo[symbol] = v
		return v
	}
	for _, s := range g.Order {
		context(s)
	}
	return memo
}
func setsFile(g Grammar, sets Sets, sentences map[string][]string) []string {
	lines := []string{fmt.Sprintf("passes: nullable=%d first=%d follow=%d", sets.NullablePasses, sets.FirstPasses, sets.FollowPasses), ""}
	for _, lhs := range g.Order {
		nullable := "no"
		if sets.Nullable[lhs] {
			nullable = "yes"
		}
		lines = append(lines, lhs, "  nullable: "+nullable, listLine("  first:", terminalOrder(sets.First[lhs])),
			listLine("  follow:", terminalOrder(sets.Follow[lhs])), listLine("  shortest:", sentences[lhs]))
	}
	return lines
}
func firstPath(start int, token string, table ParseTable, sets Sets) []int {
	byLHS := map[string][]int{}
	for _, p := range table.Productions {
		byLHS[p.LHS] = append(byLHS[p.LHS], p.Number)
	}
	queue := []int{start}
	parent := map[int]int{start: 0}
	for cursor := 0; cursor < len(queue); cursor++ {
		current := queue[cursor]
		for _, symbol := range table.Productions[current-1].RHS {
			if symbol == token {
				path := []int{}
				for current != start {
					path = append(path, current)
					current = parent[current]
				}
				slices.Reverse(path)
				return path
			}
			if isNonterminal(symbol) {
				for _, number := range byLHS[symbol] {
					if _, seen := parent[number]; !seen {
						parent[number] = current
						queue = append(queue, number)
					}
				}
				if !sets.Nullable[symbol] {
					break
				}
			} else {
				break
			}
		}
	}
	return nil
}
func followPath(lhs, token string, g Grammar, table ParseTable, sets Sets) []int {
	queue := []string{lhs}
	paths := map[string][]int{lhs: {}}
	for cursor := 0; cursor < len(queue); cursor++ {
		symbol := queue[cursor]
		path := paths[symbol]
		if symbol == g.Start && token == "$" {
			return path
		}
		for _, p := range table.Productions {
			for i, s := range p.RHS {
				if s != symbol {
					continue
				}
				more, empty := firstSequence(p.RHS[i+1:], sets.Nullable, sets.First)
				next := append(append([]int{}, path...), p.Number)
				if more[token] {
					return next
				}
				if _, seen := paths[p.LHS]; empty && !seen {
					paths[p.LHS] = next
					queue = append(queue, p.LHS)
				}
			}
		}
	}
	return nil
}
func tableFile(g Grammar, sets Sets, table ParseTable, before int) []string {
	lines := []string{"== predict sets =="}
	for _, p := range table.Productions {
		set := StringSet{}
		for t := range p.Predict {
			set[t] = true
		}
		lines = append(lines, fmt.Sprintf("%d: %s", p.Number, p.Notation), listLine("  predict:", terminalOrder(set)))
	}
	lines = append(lines, "", "== parse table ==")
	tokens := append(append([]string{}, sets.Terminals...), "$")
	matrix := [][]string{append([]string{""}, tokens...)}
	for _, lhs := range g.Order {
		row := []string{lhs}
		for _, t := range tokens {
			entries := table.Cells[CellKey{lhs, t}]
			values := []string{}
			for _, entry := range entries {
				values = append(values, strconv.Itoa(entry.Number))
			}
			value := "."
			if len(values) > 0 {
				value = strings.Join(values, "/")
			}
			row = append(row, value)
		}
		matrix = append(matrix, row)
	}
	widths := make([]int, len(tokens)+1)
	for _, row := range matrix {
		for i, s := range row {
			widths[i] = max(widths[i], len(s))
		}
	}
	for _, row := range matrix {
		line := fmt.Sprintf("%-*s", widths[0], row[0])
		for i, value := range row[1:] {
			line += fmt.Sprintf("  %*s", widths[i+1], value)
		}
		lines = append(lines, line)
	}
	lines = append(lines, "", "== conflicts ==")
	if len(table.Conflicts) == 0 {
		lines = append(lines, "none")
	}
	for _, conflict := range table.Conflicts {
		lines = append(lines, fmt.Sprintf("conflict %s on %s: %s, chosen %d", conflict.LHS, conflict.Token, conflict.Kind, conflict.Chosen))
		for _, entry := range conflict.Entries {
			p := table.Productions[entry.Number-1]
			path := []int{}
			if entry.Reason == "FIRST" {
				path = firstPath(p.Number, conflict.Token, table, sets)
			} else {
				path = followPath(conflict.LHS, conflict.Token, g, table, sets)
			}
			reason := entry.Reason
			if len(path) > 0 {
				reason = listLine(reason+" via", intStrings(path))
			}
			lines = append(lines, fmt.Sprintf("  %d: %s (%s)", p.Number, p.Notation, reason))
		}
	}
	status := "yes"
	if len(table.Conflicts) > 0 {
		status = "no"
	}
	return append(lines, "LL(1): "+status, fmt.Sprintf("conflicts before transformation: %d", before))
}
func compactTree(node *TreeNode) *TreeNode {
	children := []*TreeNode{}
	for _, original := range node.Children {
		if original.Symbol == "%empty" {
			continue
		}
		child := compactTree(original)
		if isNonterminal(child.Symbol) && child.Mark == "" && len(child.Children) == 0 {
			continue
		}
		if isNonterminal(child.Symbol) && strings.Contains(child.Symbol, "'") && child.Mark == "" {
			children = append(children, child.Children...)
		} else {
			children = append(children, child)
		}
	}
	if len(children) == 1 && node.Mark == "" {
		return children[0]
	}
	return &TreeNode{node.Symbol, node.Mark, children}
}
func treeLines(root *TreeNode) []string {
	lines := []string{treeLabel(root)}
	var visit func(*TreeNode, string, bool)
	visit = func(node *TreeNode, prefix string, last bool) {
		branch, next := "|-- ", "|   "
		if last {
			branch, next = "`-- ", "    "
		}
		lines = append(lines, prefix+branch+treeLabel(node))
		for i, child := range node.Children {
			visit(child, prefix+next, i == len(node.Children)-1)
		}
	}
	for i, child := range root.Children {
		visit(child, "", i == len(root.Children)-1)
	}
	return lines
}
func traceLines(trace [][4]string) []string {
	rows := append([][4]string{{"step", "stack", "input", "action"}}, trace...)
	widths := [3]int{}
	for _, row := range rows {
		for i := range widths {
			widths[i] = max(widths[i], len(row[i]))
		}
	}
	lines := []string{}
	for _, row := range rows {
		lines = append(lines, fmt.Sprintf("%-*s  %-*s  %-*s  %s", widths[0], row[0], widths[1], row[1], widths[2], row[2], row[3]))
	}
	return lines
}
func leftmostDerivation(start string, numbers []int, productions []Production) []string {
	symbols := []string{start}
	lines := []string{"  " + start}
	for _, number := range numbers {
		position := 0
		for !isNonterminal(symbols[position]) {
			position++
		}
		symbols = concatenate(symbols[:position], productions[number-1].RHS, symbols[position+1:])
		lines = append(lines, "  => "+notation(symbols))
	}
	return lines
}

type EarleyState struct{ Production, Dot, Origin int }

func recognizeLanguage(g Grammar, tokens []string) bool {
	productions := append([]Production{{LHS: "<__root>", RHS: []string{g.Start}}}, numberProductions(g)...)
	byLHS := map[string][]int{}
	for i, p := range productions[1:] {
		byLHS[p.LHS] = append(byLHS[p.LHS], i+1)
	}
	chart := make([]map[EarleyState]bool, len(tokens)+1)
	pending := make([][]EarleyState, len(chart))
	for i := range chart {
		chart[i] = map[EarleyState]bool{}
	}
	add := func(position int, item EarleyState) {
		if !chart[position][item] {
			chart[position][item] = true
			pending[position] = append(pending[position], item)
		}
	}
	add(0, EarleyState{})
	for position := 0; position <= len(tokens); position++ {
		for cursor := 0; cursor < len(pending[position]); cursor++ {
			state := pending[position][cursor]
			p := productions[state.Production]
			if state.Dot == len(p.RHS) {
				for _, waiting := range pending[state.Origin] {
					body := productions[waiting.Production].RHS
					if waiting.Dot < len(body) && body[waiting.Dot] == p.LHS {
						add(position, EarleyState{waiting.Production, waiting.Dot + 1, waiting.Origin})
					}
				}
			} else {
				symbol := p.RHS[state.Dot]
				if isNonterminal(symbol) {
					for _, number := range byLHS[symbol] {
						add(position, EarleyState{number, 0, position})
					}
					for _, done := range pending[position] {
						completed := productions[done.Production]
						if completed.LHS == symbol && done.Dot == len(completed.RHS) && done.Origin == position {
							add(position, EarleyState{state.Production, state.Dot + 1, state.Origin})
						}
					}
				} else if position < len(tokens) && symbol == tokens[position] {
					add(position+1, EarleyState{state.Production, state.Dot + 1, state.Origin})
				}
			}
		}
	}
	return chart[len(tokens)][EarleyState{0, 1, 0}]
}
func parseInput(tokens []string, g Grammar, sets Sets, table ParseTable) ParseResult {
	known := StringSet{}
	for _, t := range sets.Terminals {
		known[t] = true
	}
	kept := []InputToken{}
	unknown := []string{}
	for i, t := range tokens {
		if known[t] {
			kept = append(kept, InputToken{t, i + 1})
		} else {
			unknown = append(unknown, fmt.Sprintf("unknown \"%s\" at token %d; removed", t, i+1))
		}
	}
	out := parseTokens(kept, g, sets, table)
	out.Original = tokens
	out.UnknownErrors = unknown
	out.Accepted = len(unknown) == 0 && len(out.Errors) == 0
	return out
}
func oneParseReport(index int, p ParseResult, g Grammar, table ParseTable) []string {
	errors := concatenate(p.UnknownErrors, p.Errors)
	lines := []string{fmt.Sprintf("== input %d ==", index), listLine("tokens:", p.Original)}
	lines = append(lines, traceLines(p.Trace)...)
	lines = append(lines, listLine("left parse:", intStrings(p.LeftParse)), fmt.Sprintf("stats: steps=%d predicts=%d matches=%d max_stack=%d",
		len(p.Trace), p.Predicts, p.Matches, p.MaxStack))
	if len(errors) > 0 {
		lines = append(lines, "errors:")
		for _, e := range errors {
			lines = append(lines, "  "+e)
		}
	}
	result := "result: accepted"
	if !p.Accepted {
		result = fmt.Sprintf("result: rejected (errors: %d)", len(errors))
	}
	language := "no"
	if p.Language {
		language = "yes"
	}
	lines = append(lines, result, "language: "+language)
	if p.Accepted {
		lines = append(lines, "derivation:")
		lines = append(lines, leftmostDerivation(g.Start, p.LeftParse, table.Productions)...)
	}
	lines = append(lines, "tree:")
	lines = append(lines, treeLines(p.Root)...)
	lines = append(lines, "compact tree:")
	return append(lines, treeLines(compactTree(p.Root))...)
}
func parseReport(inputs []ParseResult, g Grammar, sets Sets, table ParseTable, sentences map[string][]string, contexts map[string]Context) []string {
	lines := []string{}
	accepted, inLanguage, unknown, skip, pop, missing := 0, 0, 0, 0, 0, 0
	mismatches := []int{}
	used := map[int]bool{}
	for i, p := range inputs {
		lines = append(lines, oneParseReport(i+1, p, g, table)...)
		lines = append(lines, "")
		if p.Accepted {
			accepted++
		}
		if p.Language {
			inLanguage++
		}
		if p.Accepted != p.Language {
			mismatches = append(mismatches, i+1)
		}
		unknown += len(p.UnknownErrors)
		skip += p.Skip
		pop += p.Pop
		missing += p.Missing
		for _, number := range p.LeftParse {
			used[number] = true
		}
	}
	unused := []int{}
	for _, p := range table.Productions {
		if !used[p.Number] {
			unused = append(unused, p.Number)
		}
	}
	lines = append(lines, "== summary ==", fmt.Sprintf("inputs=%d accepted=%d rejected=%d in_language=%d",
		len(inputs), accepted, len(inputs)-accepted, inLanguage), listLine("mismatches:", intStrings(mismatches)),
		fmt.Sprintf("recovery: unknown=%d skip=%d pop=%d missing=%d", unknown, skip, pop, missing),
		fmt.Sprintf("coverage: %d of %d productions used", len(used), len(table.Productions)), listLine("unused:",
			intStrings(unused)))
	for _, number := range unused {
		p := table.Productions[number-1]
		context := contexts[p.LHS]
		sentence := concatenate(context.Prefix, expandSequence(p.RHS, sentences), context.Suffix)
		tokens := []InputToken{}
		for i, t := range sentence {
			tokens = append(tokens, InputToken{t, i + 1})
		}
		parsed := parseTokens(tokens, g, sets, table)
		errors := parsed.Skip + parsed.Pop + parsed.Missing
		result := "    result: accepted"
		if errors > 0 {
			result = fmt.Sprintf("    result: rejected (errors: %d)", errors)
		}
		status := "no"
		if slices.Contains(parsed.LeftParse, number) {
			status = "yes"
		}
		lines = append(lines, fmt.Sprintf("  %d: %s", number, p.Notation), listLine("    example:", sentence), result, "    used: "+status)
	}
	return lines
}
func save(name string, lines []string) {
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	if e := os.WriteFile("output/"+name, []byte(strings.Join(lines, "\n")+"\n"), 0644); e != nil {
		panic(e)
	}
}
func main() {
	source := parseGrammar()
	declarations := checkDeclarations(source)
	cleaned, cleanDiags := cleanGrammar(source)
	recursionDiags := recursionDiagnostics(cleaned)
	recursion, recursionLog := eliminateLeftRecursion(cleaned)
	factored, factoringLog := leftFactor(recursion)
	final, finalLog, finalDiags := finalPruning(factored)
	unusedDiags := unusedDeclarations(source, final)
	beforeSets := analyzeSets(cleaned)
	beforeTable := buildTable(cleaned, beforeSets)
	sets := analyzeSets(final)
	table := buildTable(final, sets)
	scores, sentences := shortestSentences(final)
	contexts := shortestContexts(final, scores, sentences)
	inputs := []ParseResult{}
	for _, line := range readLines("input/inputs.txt") {
		tokens := []string{}
		if line != "" {
			tokens = strings.Split(line, " ")
		}
		parsed := parseInput(tokens, final, sets, table)
		parsed.Language = recognizeLanguage(cleaned, tokens)
		inputs = append(inputs, parsed)
	}
	diagnostics := concatenate(source.Diagnostics, declarations, cleanDiags, recursionDiags, finalDiags, unusedDiags)
	if len(table.Conflicts) > 0 {
		diagnostics = append(diagnostics, fmt.Sprintf("result: not LL(1) (conflicts: %d)", len(table.Conflicts)))
	} else {
		diagnostics = append(diagnostics, "result: LL(1)")
	}
	save("grammar.txt", grammarFile(cleaned, recursion, factored, final, recursionLog, factoringLog, finalLog))
	save("sets.txt", setsFile(final, sets, sentences))
	save("table.txt", tableFile(final, sets, table, len(beforeTable.Conflicts)))
	save("parses.txt", parseReport(inputs, final, sets, table, sentences, contexts))
	save("diagnostics.txt", diagnostics)
}
