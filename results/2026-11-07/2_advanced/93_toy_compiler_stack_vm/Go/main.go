package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

type Source struct {
	Name      string
	FirstLine int
	Lines     []string
}
type Warning struct {
	Position
	Message string
}

var ruleNames = []string{"const-jump", "not-compare", "not-jump", "invert-branch", "thread", "jump-next", "unreachable"}

func reachableFunctions(p *Program) map[*Symbol]bool {
	reachable := map[*Symbol]bool{}
	var visit func(*Symbol)
	visit = func(f *Symbol) {
		if reachable[f] {
			return
		}
		reachable[f] = true
		for callee := range f.Calls {
			visit(callee)
		}
	}
	visit(p.Names["main"])
	return reachable
}
func collectWarnings(p *Program, reachable map[*Symbol]bool) []Warning {
	out := []Warning{}
	for _, symbol := range p.Symbols {
		if symbol.Kind != "function" && symbol.Reads == 0 {
			kind := "variable"
			if symbol.Kind == "parameter" {
				kind = "parameter"
			}
			out = append(out, Warning{symbol.Declaration.Name.Position, "unused " + kind + " '" + symbol.Name + "'"})
		}
	}
	for _, f := range p.Functions {
		if !reachable[f.Symbol] {
			out = append(out, Warning{f.Name.Position, "function '" + f.Name.Spelling + "' is never called"})
		}
		walkStatements(f.Body, func(s *Statement) {
			if s.Kind != "block" {
				return
			}
			for i, child := range s.Statements {
				if !canComplete(child) {
					if i+1 < len(s.Statements) {
						out = append(out, Warning{s.Statements[i+1].Token.Position, "unreachable statement"})
					}
					break
				}
			}
		})
	}
	sort.Slice(out, func(i, j int) bool { return earlier(out[i].Position, out[j].Position) })
	return out
}
func literal(e *Expr) bool { return e.Kind == "integer" || e.Kind == "boolean" }
func inRange(v int64) bool { return v >= -2147483648 && v <= 2147483647 }
func foldedLiteral(e *Expr, value int64) *Expr {
	kind := "integer"
	if e.Type == "bool" {
		kind = "boolean"
	}
	return &Expr{Kind: kind, Type: e.Type, Token: e.Token, Value: value}
}
func constantBinary(op string, a, b int64) (int64, bool) {
	value := int64(0)
	answer := false
	switch op {
	case "+":
		value = a + b
		return value, inRange(value)
	case "-":
		value = a - b
		return value, inRange(value)
	case "*":
		value = a * b
		return value, inRange(value)
	case "/", "%":
		if b == 0 {
			return 0, false
		}
		q := a / b
		if op == "/" {
			return q, inRange(q)
		}
		return a - q*b, true
	case "<":
		answer = a < b
	case "<=":
		answer = a <= b
	case ">":
		answer = a > b
	case ">=":
		answer = a >= b
	case "==":
		answer = a == b
	case "!=":
		answer = a != b
	case "&&":
		answer = a != 0 && b != 0
	case "||":
		answer = a != 0 || b != 0
	}
	if answer {
		value = 1
	}
	return value, true
}
func foldExpression(e *Expr, count *int) *Expr {
	if e == nil {
		return nil
	}
	for i, child := range e.Children {
		e.Children[i] = foldExpression(child, count)
	}
	if e.Kind == "unary" && literal(e.Children[0]) {
		value := e.Children[0].Value
		if e.Token.Spelling == "-" {
			value = -value
			if !inRange(value) {
				return e
			}
		} else {
			if value == 0 {
				value = 1
			} else {
				value = 0
			}
		}
		*count++
		return foldedLiteral(e, value)
	}
	if e.Kind != "binary" {
		return e
	}
	left, right := e.Children[0], e.Children[1]
	op := e.Token.Spelling
	if literal(left) && literal(right) {
		if value, ok := constantBinary(op, left.Value, right.Value); ok {
			*count++
			return foldedLiteral(e, value)
		}
	}
	if literal(left) {
		if op == "&&" && left.Value == 0 || op == "||" && left.Value != 0 {
			*count++
			return foldedLiteral(e, left.Value)
		}
		if op == "&&" && left.Value != 0 || op == "||" && left.Value == 0 || op == "+" && left.Value == 0 || op == "*" && left.Value == 1 {
			*count++
			return right
		}
	}
	if literal(right) && (op == "+" && right.Value == 0 || op == "-" && right.Value == 0 || op == "*" && right.Value == 1 || op == "/" && right.Value == 1 || op == "&&" && right.Value != 0 || op == "||" && right.Value == 0) {
		*count++
		return left
	}
	return e
}
func foldStatement(s *Statement, count *int) *Statement {
	if s == nil {
		return nil
	}
	switch s.Kind {
	case "if":
		s.Condition = foldExpression(s.Condition, count)
		if literal(s.Condition) {
			var replacement *Statement
			if s.Condition.Value != 0 {
				replacement = foldStatement(s.Then, count)
			} else if s.Else != nil {
				replacement = foldStatement(s.Else, count)
			} else {
				replacement = &Statement{Kind: "empty", Token: s.Token}
			}
			*count++
			return replacement
		}
		s.Then = foldStatement(s.Then, count)
		s.Else = foldStatement(s.Else, count)
	case "while":
		s.Condition = foldExpression(s.Condition, count)
		if literal(s.Condition) && s.Condition.Value == 0 {
			*count++
			return &Statement{Kind: "empty", Token: s.Token}
		}
		s.Body = foldStatement(s.Body, count)
	case "for":
		s.Init = foldStatement(s.Init, count)
		s.Condition = foldExpression(s.Condition, count)
		s.Update = foldStatement(s.Update, count)
		s.Body = foldStatement(s.Body, count)
	case "block":
		for i, child := range s.Statements {
			s.Statements[i] = foldStatement(child, count)
		}
	case "declaration":
		s.Declaration.Initializer = foldExpression(s.Declaration.Initializer, count)
	case "assignment":
		s.Index = foldExpression(s.Index, count)
		s.Expr = foldExpression(s.Expr, count)
	case "call", "return":
		s.Expr = foldExpression(s.Expr, count)
	case "print":
		for i, e := range s.Expressions {
			s.Expressions[i] = foldExpression(e, count)
		}
	}
	return s
}
func foldProgram(p *Program, reachable map[*Symbol]bool) int {
	count := 0
	for _, d := range p.Globals {
		d.Initializer = foldExpression(d.Initializer, &count)
	}
	for _, f := range p.Functions {
		if reachable[f.Symbol] {
			f.Body = foldStatement(f.Body, &count)
		}
	}
	return count
}
func inverse(op string) string {
	if op == "JUMPF" {
		return "JUMPT"
	}
	return "JUMPF"
}
func branchTaken(op string, value int64) bool {
	return op == "JUMPF" && value == 0 || op == "JUMPT" && value != 0
}
func deleteInstruction(unit *Unit, index int) {
	unit.Code = append(unit.Code[:index], unit.Code[index+1:]...)
	for i := range unit.Code {
		if jump(unit.Code[i].Op) && unit.Code[i].A > int64(index) {
			unit.Code[i].A--
		}
	}
}
func optimize(unit *Unit) []int {
	counts := make([]int, 7)
	negations := map[string]string{"LT": "GE", "GE": "LT", "LE": "GT", "GT": "LE", "EQ": "NE", "NE": "EQ"}
	for {
		targets := map[int]bool{}
		for _, instruction := range unit.Code {
			if jump(instruction.Op) {
				targets[int(instruction.A)] = true
			}
		}
		applied := false
		for i := 0; i < len(unit.Code); i++ {
			a := unit.Code[i]
			free := i+1 < len(unit.Code) && !targets[i+1]
			var b Instruction
			if i+1 < len(unit.Code) {
				b = unit.Code[i+1]
			}
			rule := -1
			switch {
			case a.Op == "PUSH" && free && conditional(b.Op):
				if branchTaken(b.Op, a.A) {
					unit.Code[i] = Instruction{Op: "JUMP", A: b.A, Position: b.Position}
					deleteInstruction(unit, i+1)
				} else {
					deleteInstruction(unit, i+1)
					deleteInstruction(unit, i)
				}
				rule = 0
			case negations[a.Op] != "" && free && b.Op == "NOT":
				unit.Code[i].Op = negations[a.Op]
				deleteInstruction(unit, i+1)
				rule = 1
			case a.Op == "NOT" && free && conditional(b.Op):
				unit.Code[i] = Instruction{Op: inverse(b.Op), A: b.A, Position: b.Position}
				deleteInstruction(unit, i+1)
				rule = 2
			case conditional(a.Op) && a.A == int64(i+2) && free && b.Op == "JUMP":
				unit.Code[i] = Instruction{Op: inverse(a.Op), A: b.A, Position: a.Position}
				deleteInstruction(unit, i+1)
				rule = 3
			default:
				if jump(a.Op) && int(a.A) < len(unit.Code) {
					t := int(a.A)
					target := unit.Code[t]
					newTarget := -1
					if target.Op == "JUMP" {
						newTarget = int(target.A)
					} else if target.Op == "PUSH" && t+1 < len(unit.Code) && conditional(unit.Code[t+1].Op) {
						next := unit.Code[t+1]
						newTarget = t + 2
						if branchTaken(next.Op, target.A) {
							newTarget = int(next.A)
						}
					}
					if newTarget >= 0 && newTarget != t {
						unit.Code[i].A = int64(newTarget)
						rule = 4
					}
				}
				if rule < 0 && jump(a.Op) && a.A == int64(i+1) {
					if a.Op == "JUMP" {
						deleteInstruction(unit, i)
					} else {
						unit.Code[i] = Instruction{Op: "POP", Position: a.Position}
					}
					rule = 5
				}
				if rule < 0 && transfer(a.Op) && free {
					deleteInstruction(unit, i+1)
					rule = 6
				}
			}
			if rule >= 0 {
				counts[rule]++
				applied = true
				break
			}
		}
		if !applied {
			return counts
		}
	}
}
func arrange(units []*Unit) int {
	start := 0
	starts := map[*Declaration]int{}
	for _, unit := range units {
		unit.Start = start
		starts[unit.Function] = start
		start += len(unit.Code)
	}
	for _, unit := range units {
		for i := range unit.Code {
			if unit.Code[i].Op == "CALL" {
				unit.Code[i].A = int64(starts[unit.Code[i].Callee])
			}
		}
	}
	return start
}
func stackEffect(instruction Instruction) int {
	switch instruction.Op {
	case "PUSH", "LOADG", "LOADL", "READ":
		return 1
	case "POP", "STOREG", "STOREL", "JUMPF", "JUMPT", "RETV", "ADD", "SUB", "MUL", "DIV", "MOD", "LT", "LE", "GT", "GE", "EQ", "NE":
		return -1
	case "STOREA":
		return -2
	case "CALL":
		effect := -int(instruction.B)
		if instruction.Callee.Type != "void" {
			effect++
		}
		return effect
	case "PRINT":
		return -int(instruction.A)
	}
	return 0
}
func analyzeUnit(unit *Unit) {
	n := len(unit.Code)
	leaders := map[int]bool{0: true}
	for i, instruction := range unit.Code {
		if jump(instruction.Op) && int(instruction.A) < n {
			leaders[int(instruction.A)] = true
		}
		if (jump(instruction.Op) || transfer(instruction.Op)) && i+1 < n {
			leaders[i+1] = true
		}
	}
	indices := []int{}
	for i := range leaders {
		indices = append(indices, i)
	}
	sort.Ints(indices)
	blockOf := make([]int, n)
	for k, first := range indices {
		last := n - 1
		if k+1 < len(indices) {
			last = indices[k+1] - 1
		}
		for i := first; i <= last; i++ {
			blockOf[i] = k
		}
		unit.Blocks = append(unit.Blocks, BasicBlock{First: first, Last: last})
	}
	for k, block := range unit.Blocks {
		last := unit.Code[block.Last]
		successors := []int{}
		if last.Op == "JUMP" {
			successors = append(successors, int(last.A))
		} else if conditional(last.Op) {
			successors = append(successors, block.Last+1, int(last.A))
		} else if !transfer(last.Op) {
			successors = append(successors, block.Last+1)
		}
		seen := map[int]bool{}
		for _, index := range successors {
			if index < n && !seen[blockOf[index]] {
				unit.Blocks[k].Successors = append(unit.Blocks[k].Successors, blockOf[index])
				seen[blockOf[index]] = true
			}
		}
	}
	depths := make([]int, n)
	for i := range depths {
		depths[i] = -1
	}
	depths[0] = 0
	queue := []int{0}
	for head := 0; head < len(queue); head++ {
		i := queue[head]
		instruction := unit.Code[i]
		nextDepth := depths[i] + stackEffect(instruction)
		unit.Stack = max(unit.Stack, nextDepth)
		next := []int{}
		if !transfer(instruction.Op) && i+1 < n {
			next = append(next, i+1)
		}
		if jump(instruction.Op) && int(instruction.A) < n {
			next = append(next, int(instruction.A))
		}
		for _, j := range next {
			if depths[j] < 0 {
				depths[j] = nextDepth
				queue = append(queue, j)
			}
		}
	}
}
func recursive(function *Symbol) bool {
	seen := map[*Symbol]bool{}
	var visit func(*Symbol) bool
	visit = func(current *Symbol) bool {
		seen[current] = true
		for callee := range current.Calls {
			if callee == function {
				return true
			}
			if !seen[callee] && visit(callee) {
				return true
			}
		}
		return false
	}
	return visit(function)
}
func spelling(instruction Instruction, start int) string {
	out := instruction.Op
	a := instruction.A
	if jump(instruction.Op) {
		a += int64(start)
	}
	if wordIn("PUSH LOADG STOREG LOADL STOREL LOADA STOREA JUMP JUMPF JUMPT CALL ENTER PRINT", instruction.Op) {
		out += " " + strconv.FormatInt(a, 10)
	}
	if instruction.Op == "LOADA" || instruction.Op == "STOREA" || instruction.Op == "CALL" {
		out += " " + strconv.FormatInt(instruction.B, 10)
	}
	return out
}
func callees(symbol *Symbol) string {
	names := []string{}
	for callee := range symbol.Calls {
		names = append(names, callee.Name)
	}
	sort.Strings(names)
	if len(names) == 0 {
		return "-"
	}
	return strings.Join(names, ",")
}
func listing(p *Program, before, after []*Unit, beforeCount, afterCount int) []string {
	out := []string{}
	if len(p.Globals) == 0 {
		out = append(out, "globals: none")
	} else {
		out = append(out, "globals:")
		for _, d := range p.Globals {
			typ := d.Type
			if d.Array {
				typ = fmt.Sprintf("int[%d]", d.Size.Integer)
			}
			out = append(out, fmt.Sprintf("  %d %s %s", d.Symbol.Address, d.Name.Spelling, typ))
		}
	}
	out = append(out, "functions:")
	for i, unit := range after {
		signature, calls, suffix := "", "main", ""
		if unit.Function != nil {
			f := unit.Function
			parameters := []string{}
			for _, p := range f.Parameters {
				parameters = append(parameters, p.Type)
			}
			signature = " " + f.Type + "(" + strings.Join(parameters, ",") + ")"
			calls = callees(f.Symbol)
			if recursive(f.Symbol) {
				suffix = " recursive"
			}
		}
		out = append(out, fmt.Sprintf("  %s%s address=%d->%d size=%d->%d slots=%d stack=%d blocks=%d calls=%s%s", unit.Name, signature, before[i].Start, unit.Start, len(before[i].Code), len(unit.Code), unit.Slots, unit.Stack, len(unit.Blocks), calls, suffix))
		if unit.Function != nil {
			for slot, symbol := range unit.Function.Slots {
				out = append(out, fmt.Sprintf("    slot %d %s %s", slot, symbol.Name, symbol.Type))
			}
		}
	}
	out = append(out, "references:")
	declarations := append(append([]*Declaration{}, p.Globals...), p.Functions...)
	for _, d := range declarations {
		lines := map[int]bool{}
		for _, position := range d.Symbol.References {
			lines[position.Line] = true
		}
		ordered := []int{}
		for line := range lines {
			ordered = append(ordered, line)
		}
		sort.Ints(ordered)
		used := []string{}
		for _, line := range ordered {
			used = append(used, strconv.Itoa(line))
		}
		value := strings.Join(used, " ")
		if value == "" {
			value = "-"
		}
		out = append(out, fmt.Sprintf("  %s defined %d used %s", d.Name.Spelling, d.Name.Line, value))
	}
	for pass, units := range [][]*Unit{before, after} {
		label, count := "before", beforeCount
		if pass == 1 {
			label = "after"
			count = afterCount
		}
		out = append(out, fmt.Sprintf("%s peephole: %d instructions", label, count))
		for _, unit := range units {
			out = append(out, unit.Name+":")
			for i, instruction := range unit.Code {
				out = append(out, fmt.Sprintf("%5d  %s", unit.Start+i, spelling(instruction, unit.Start)))
			}
		}
	}
	out = append(out, "control flow:")
	for _, unit := range after {
		out = append(out, "  "+unit.Name)
		for k, block := range unit.Blocks {
			line := fmt.Sprintf("    B%d %d-%d", k, unit.Start+block.First, unit.Start+block.Last)
			if len(block.Successors) > 0 {
				names := []string{}
				for _, successor := range block.Successors {
					names = append(names, fmt.Sprintf("B%d", successor))
				}
				line += " -> " + strings.Join(names, " ")
			}
			out = append(out, line)
		}
	}
	return out
}
func sameBehavior(a, b *RunResult) bool {
	if a.Error != b.Error || len(a.Output) != len(b.Output) {
		return false
	}
	for i, line := range a.Output {
		if line != b.Output[i] {
			return false
		}
	}
	return true
}
func sumCounts(counts []int) int {
	sum := 0
	for _, count := range counts {
		sum += count
	}
	return sum
}

type NamedCount struct {
	Name  string
	Count int
}

func sortedCounts(counts map[string]int, positive bool) []NamedCount {
	out := []NamedCount{}
	for name, count := range counts {
		if !positive || count > 0 {
			out = append(out, NamedCount{name, count})
		}
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Count != out[j].Count {
			return out[i].Count > out[j].Count
		}
		return out[i].Name < out[j].Name
	})
	return out
}
func statsLines(units []*Unit, beforeCount, afterCount, folds int, rules []int, run, comparison *RunResult) []string {
	behaviour := "different"
	if sameBehavior(run, comparison) {
		behaviour = "same"
	}
	out := []string{fmt.Sprintf("code: %d -> %d", beforeCount, afterCount), fmt.Sprintf("folds: %d", folds), fmt.Sprintf("peephole: %d", sumCounts(rules))}
	for i, name := range ruleNames {
		out = append(out, fmt.Sprintf("  %s %d", name, rules[i]))
	}
	out = append(out, fmt.Sprintf("executed: %d", run.Executed), fmt.Sprintf("executed before peephole: %d", comparison.Executed), "behaviour: "+behaviour, fmt.Sprintf("max call depth: %d", run.MaximumDepth), fmt.Sprintf("max stack: %d", run.MaximumStack), "opcodes:")
	code := flatten(units)
	opcodes := map[string]int{}
	functions := map[string]int{}
	lineCounts := map[int]int{}
	for _, unit := range units {
		if unit.Function != nil {
			functions[unit.Name] = 0
		}
	}
	for pc, instruction := range code {
		count := run.Counts[pc]
		opcodes[instruction.Op] += count
		if instruction.Unit.Function != nil {
			functions[instruction.Unit.Name] += count
		}
		lineCounts[instruction.Line] += count
	}
	for _, record := range sortedCounts(opcodes, true) {
		out = append(out, fmt.Sprintf("  %s %d", record.Name, record.Count))
	}
	out = append(out, "functions:")
	for _, record := range sortedCounts(functions, false) {
		out = append(out, fmt.Sprintf("  %s calls=%d executed=%d", record.Name, run.Calls[record.Name], record.Count))
	}
	out = append(out, "calls:")
	pairs := [][2]string{}
	for pair, count := range run.Pairs {
		if count > 0 {
			pairs = append(pairs, pair)
		}
	}
	sort.Slice(pairs, func(i, j int) bool {
		a, b := pairs[i], pairs[j]
		if run.Pairs[a] != run.Pairs[b] {
			return run.Pairs[a] > run.Pairs[b]
		}
		if a[0] != b[0] {
			return a[0] < b[0]
		}
		return a[1] < b[1]
	})
	for _, pair := range pairs {
		out = append(out, fmt.Sprintf("  %s -> %s %d", pair[0], pair[1], run.Pairs[pair]))
	}
	positive, negative := []int{}, []int{}
	for line, count := range lineCounts {
		if count > 0 {
			positive = append(positive, line)
		} else {
			negative = append(negative, line)
		}
	}
	sort.Slice(positive, func(i, j int) bool {
		if lineCounts[positive[i]] != lineCounts[positive[j]] {
			return lineCounts[positive[i]] > lineCounts[positive[j]]
		}
		return positive[i] < positive[j]
	})
	sort.Ints(negative)
	out = append(out, "hot lines:")
	for _, line := range positive[:min(5, len(positive))] {
		out = append(out, fmt.Sprintf("  line %d: %d", line, lineCounts[line]))
	}
	out = append(out, fmt.Sprintf("coverage: %d of %d lines", len(positive), len(lineCounts)))
	missing := []string{}
	for _, line := range negative {
		missing = append(missing, strconv.Itoa(line))
	}
	unexecuted := "none"
	if len(missing) > 0 {
		unexecuted = strings.Join(missing, " ")
	}
	out = append(out, "not executed: "+unexecuted, "hot spots:")
	pcs := []int{}
	for pc, count := range run.Counts {
		if count > 0 {
			pcs = append(pcs, pc)
		}
	}
	sort.Slice(pcs, func(i, j int) bool {
		if run.Counts[pcs[i]] != run.Counts[pcs[j]] {
			return run.Counts[pcs[i]] > run.Counts[pcs[j]]
		}
		return pcs[i] < pcs[j]
	})
	for _, pc := range pcs[:min(5, len(pcs))] {
		instruction := code[pc]
		out = append(out, fmt.Sprintf("  pc=%d count=%d %s", pc, run.Counts[pc], spelling(instruction.Instruction, 0)))
	}
	return out
}
func positionDisplay(pos Position, allLines []string) []string {
	return []string{"  " + allLines[pos.Line-1], strings.Repeat(" ", pos.Column+1) + "^"}
}
func runtimeDiagnostics(units []*Unit, run *RunResult, allLines []string) []string {
	code := flatten(units)
	instruction := code[run.FaultPC]
	out := []string{fmt.Sprintf("runtime error %s: %s in %s", instruction.Position, run.Error, instruction.Unit.Name)}
	out = append(out, positionDisplay(instruction.Position, allLines)...)
	count := max(0, len(run.Frames)-1)
	shown := 0
	for i := len(run.Frames) - 1; i >= 1 && shown < 5; i-- {
		caller := code[run.Frames[i].Return-1]
		out = append(out, fmt.Sprintf("  called from %s at %s", caller.Unit.Name, caller.Position))
		shown++
	}
	if count > shown {
		out = append(out, fmt.Sprintf("  ... %d more", count-shown))
	}
	return out
}
func readLines(path string) []string {
	f, err := os.Open(path)
	if err != nil {
		panic(err)
	}
	defer f.Close()
	lines := []string{}
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		lines = append(lines, scanner.Text())
	}
	if err = scanner.Err(); err != nil {
		panic(err)
	}
	return lines
}
func sources(lines []string) []Source {
	out := []Source{}
	for i, line := range lines {
		if strings.HasPrefix(line, "#program ") {
			out = append(out, Source{Name: strings.TrimPrefix(line, "#program "), FirstLine: i + 2})
		} else {
			out[len(out)-1].Lines = append(out[len(out)-1].Lines, line)
		}
	}
	return out
}
func inputs() map[string][]int64 {
	out := map[string][]int64{}
	name := ""
	for _, line := range readLines("input/input.txt") {
		if strings.HasPrefix(line, "#input ") {
			name = strings.TrimPrefix(line, "#input ")
			out[name] = []int64{}
		} else {
			for _, word := range strings.Split(line, " ") {
				value, _ := strconv.ParseInt(word, 10, 64)
				out[name] = append(out[name], value)
			}
		}
	}
	return out
}
func writeLines(path string, lines []string) {
	if err := os.WriteFile("output/"+path, []byte(strings.Join(lines, "\n")+"\n"), 0644); err != nil {
		panic(err)
	}
}
func main() {
	allLines := readLines("input/program.src")
	programs := sources(allLines)
	input := inputs()
	listingReport, output, diagnostics, statistics := []string{}, []string{}, []string{}, []string{}
	compiled, runtimeErrors, totalFolds, totalExecuted := 0, 0, 0, 0
	errors := map[string]int{}
	totalRules := make([]int, 7)
	table := [][]string{{"program", "status", "code", "executed", "output"}}
	for _, source := range programs {
		heading := "== program " + source.Name + " =="
		listingReport = append(listingReport, heading)
		output = append(output, heading)
		diagnostics = append(diagnostics, heading)
		statistics = append(statistics, heading)
		tokens, err := tokenize(source.Lines, source.FirstLine)
		var program *Program
		if err == nil {
			program, err = parse(tokens)
		}
		if err == nil {
			err = analyze(program)
		}
		if err != nil {
			errors[err.Kind]++
			listingReport = append(listingReport, "not compiled")
			statistics = append(statistics, "not compiled")
			diagnostics = append(diagnostics, fmt.Sprintf("%s error %s: %s", err.Kind, err.Position, err.Message))
			diagnostics = append(diagnostics, positionDisplay(err.Position, allLines)...)
			diagnostics = append(diagnostics, "status: compile error")
			table = append(table, []string{source.Name, err.Kind + " error", "-", "-", "-"})
			continue
		}
		compiled++
		reachable := reachableFunctions(program)
		warnings := collectWarnings(program, reachable)
		for _, warning := range warnings {
			diagnostics = append(diagnostics, fmt.Sprintf("warning %s: %s", warning.Position, warning.Message))
		}
		folds := foldProgram(program, reachable)
		before, cells := generate(program, reachable)
		beforeCount := arrange(before)
		after := []*Unit{}
		rules := make([]int, 7)
		for _, original := range before {
			unit := &Unit{Name: original.Name, Function: original.Function, Code: append([]Instruction{}, original.Code...), Slots: original.Slots}
			counts := optimize(unit)
			for i, count := range counts {
				rules[i] += count
			}
			analyzeUnit(unit)
			after = append(after, unit)
		}
		afterCount := arrange(after)
		listingReport = append(listingReport, listing(program, before, after, beforeCount, afterCount)...)
		run := execute(after, cells, input[source.Name])
		comparison := execute(before, cells, input[source.Name])
		output = append(output, run.Output...)
		status := "ok"
		if run.Error != "" {
			runtimeErrors++
			status = "runtime error"
			diagnostics = append(diagnostics, runtimeDiagnostics(after, run, allLines)...)
		}
		diagnostics = append(diagnostics, "status: "+status)
		statistics = append(statistics, statsLines(after, beforeCount, afterCount, folds, rules, run, comparison)...)
		totalFolds += folds
		totalExecuted += run.Executed
		for i, count := range rules {
			totalRules[i] += count
		}
		table = append(table, []string{source.Name, status, strconv.Itoa(afterCount), strconv.Itoa(run.Executed), strconv.Itoa(len(run.Output))})
	}
	statistics = append(statistics, "== summary ==", fmt.Sprintf("programs: %d", len(programs)), fmt.Sprintf("compiled: %d", compiled), fmt.Sprintf("compile errors: lexical %d syntax %d semantic %d", errors["lexical"], errors["syntax"], errors["semantic"]), fmt.Sprintf("runtime errors: %d", runtimeErrors), fmt.Sprintf("folds: %d", totalFolds), fmt.Sprintf("peephole: %d", sumCounts(totalRules)))
	for i, name := range ruleNames {
		statistics = append(statistics, fmt.Sprintf("  %s %d", name, totalRules[i]))
	}
	statistics = append(statistics, fmt.Sprintf("executed: %d", totalExecuted))
	widths := make([]int, 5)
	for _, row := range table {
		for i, value := range row {
			widths[i] = max(widths[i], len(value))
		}
	}
	for _, row := range table {
		values := []string{}
		for i, value := range row {
			padding := strings.Repeat(" ", widths[i]-len(value))
			if i < 2 {
				values = append(values, value+padding)
			} else {
				values = append(values, padding+value)
			}
		}
		statistics = append(statistics, "  "+strings.Join(values, "  "))
	}
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	writeLines("listing.txt", listingReport)
	writeLines("output.txt", output)
	writeLines("diagnostics.txt", diagnostics)
	writeLines("stats.txt", statistics)
}
