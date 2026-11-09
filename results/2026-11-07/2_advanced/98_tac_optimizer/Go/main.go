package main

import (
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

var passOrder = []string{"constprop", "copyprop", "cse", "dce", "licm", "unreachable"}

type PassResult struct {
	Count   int
	Records []string
}

func constantPropagation(f *Function, g *CFG, d *DataFlow) PassResult {
	records := []string{}
	replacements := map[int][]CodeLine{}
	for _, b := range g.Blocks[1:] {
		if !b.Reachable {
			continue
		}
		for n := b.First; n <= b.Last; n++ {
			old := g.Instructions[n]
			copy := *old
			changed := false
			for _, a := range copy.operands() {
				if a.IsConstant {
					continue
				}
				name := a.Variable
				found, valid := false, true
				value := int64(0)
				for definition := range d.Reaching.Before[n] {
					if definition.Variable != name {
						continue
					}
					if definition.Number == 0 {
						valid = false
						break
					}
					source := g.Instructions[definition.Number]
					if source.Kind != "copy" || !source.A.IsConstant {
						valid = false
						break
					}
					if found && value != source.A.Constant {
						valid = false
						break
					}
					found = true
					value = source.A.Constant
				}
				if found && valid {
					*a = constant(value)
					records = append(records, fmt.Sprintf("#%d: %s -> %d", n, name, value))
					changed = true
				}
			}
			foldedInstruction, fold := folded(&copy)
			if fold {
				changed = true
				if copy.Kind == "if" {
					if foldedInstruction == nil {
						records = append(records, fmt.Sprintf("#%d: delete %s", n, copy.String()))
					} else {
						records = append(records, fmt.Sprintf("#%d: fold %s", n, foldedInstruction.String()))
					}
				} else {
					records = append(records, fmt.Sprintf("#%d: fold %s", n, foldedInstruction.String()))
				}
			}
			if changed {
				if foldedInstruction == nil {
					replacements[n] = nil
				} else {
					replacements[n] = []CodeLine{instructionLine(foldedInstruction)}
				}
			}
		}
	}
	rewrite(f, replacements, nil)
	return PassResult{len(records), records}
}
func copyPropagation(f *Function, g *CFG, d *DataFlow) PassResult {
	records := []string{}
	replacements := map[int][]CodeLine{}
	for _, b := range g.Blocks[1:] {
		if !b.Reachable {
			continue
		}
		for n := b.First; n <= b.Last; n++ {
			copy := *g.Instructions[n]
			changed := false
			for _, a := range copy.operands() {
				if a.IsConstant {
					continue
				}
				for pair := range d.Copies.Before[n] {
					if pair.Destination == a.Variable {
						records = append(records, fmt.Sprintf("#%d: %s -> %s", n, a.Variable, pair.Source))
						a.Variable = pair.Source
						changed = true
						break
					}
				}
			}
			if changed {
				replacements[n] = []CodeLine{instructionLine(&copy)}
			}
		}
	}
	rewrite(f, replacements, nil)
	return PassResult{len(records), records}
}

type CSEGroup struct {
	Expression Expression
	Candidates []int
}

func commonSubexpressions(f *Function, g *CFG, d *DataFlow) PassResult {
	groups := []*CSEGroup{}
	byExpression := map[Expression]*CSEGroup{}
	for _, b := range g.Blocks[1:] {
		if !b.Reachable {
			continue
		}
		for n := b.First; n <= b.Last; n++ {
			e, ok := g.Instructions[n].expression()
			if !ok || !d.Expressions.Before[n][e] {
				continue
			}
			group := byExpression[e]
			if group == nil {
				group = &CSEGroup{Expression: e}
				byExpression[e] = group
				groups = append(groups, group)
			}
			group.Candidates = append(group.Candidates, n)
		}
	}
	replacements := map[int][]CodeLine{}
	records := []string{}
	count := 0
	for _, group := range groups {
		candidates := Set[int]{}
		sources := Set[int]{}
		for _, n := range group.Candidates {
			candidates[n] = true
		}
		computes := func(n int) bool {
			e, ok := g.Instructions[n].expression()
			return ok && e == group.Expression
		}
		for _, n := range group.Candidates {
			b := g.Blocks[g.BlockOf[n]]
			found := false
			for i := n - 1; i >= b.First; i-- {
				if computes(i) {
					sources[i] = true
					found = true
					break
				}
			}
			if found {
				continue
			}
			queue := append([]int{}, b.Predecessors...)
			visited := Set[int]{}
			for len(queue) > 0 {
				p := queue[len(queue)-1]
				queue = queue[:len(queue)-1]
				if !g.Reachable[p] || visited[p] {
					continue
				}
				visited[p] = true
				block := g.Blocks[p]
				found = false
				for i := block.Last; i >= block.First; i-- {
					if computes(i) {
						sources[i] = true
						found = true
						break
					}
				}
				if !found {
					queue = append(queue, block.Predecessors...)
				}
			}
		}
		for n := range candidates {
			delete(sources, n)
		}
		temporary, edits := cseReplacements(f, g, sources, candidates)
		for n, lines := range edits {
			replacements[n] = lines
		}
		records = append(records, fmt.Sprintf("%s: %s sources=%s replaced=%s", group.Expression.String(), temporary, instructionList(sortedInts(sources)), instructionList(group.Candidates)))
		count += len(group.Candidates)
	}
	rewrite(f, replacements, nil)
	return PassResult{count, records}
}
func deadCode(f *Function, g *CFG, d *DataFlow) PassResult {
	replacements := map[int][]CodeLine{}
	records := map[int]string{}
	for _, b := range g.Blocks[1:] {
		if !b.Reachable {
			continue
		}
		live := cloneSet(d.LiveOut[b.Number])
		for n := b.Last; n >= b.First; n-- {
			s := g.Instructions[n]
			if s.Kind == "copy" && !s.A.IsConstant && s.Destination == s.A.Variable || (s.Kind == "copy" || s.Kind == "bin" || s.Kind == "load") && !live[s.Destination] {
				replacements[n] = nil
				records[n] = fmt.Sprintf("#%d: delete %s", n, s.String())
				continue
			}
			if s.Kind == "call" && s.Destination != "" && !live[s.Destination] {
				copy := *s
				copy.Destination = ""
				replacements[n] = []CodeLine{instructionLine(&copy)}
				records[n] = fmt.Sprintf("#%d: unused result %s", n, s.String())
				s = &copy
			}
			live = liveTransfer(s, live)
		}
	}
	numbers := Set[int]{}
	for n := range records {
		numbers[n] = true
	}
	lines := []string{}
	for _, n := range sortedInts(numbers) {
		lines = append(lines, records[n])
	}
	rewrite(f, replacements, nil)
	return PassResult{len(lines), lines}
}
func invariantMotion(f *Function, g *CFG, d *DataFlow) PassResult {
	loops := append([]*Loop{}, g.Loops...)
	sort.Slice(loops, func(i, j int) bool {
		if len(loops[i].Blocks) != len(loops[j].Blocks) {
			return len(loops[i].Blocks) < len(loops[j].Blocks)
		}
		return loops[i].Header < loops[j].Header
	})
	for _, loop := range loops {
		instructions := []int{}
		inside := Set[int]{}
		definitionCounts := map[string]int{}
		stores := Set[string]{}
		hasCall := false
		for _, b := range g.Blocks[1:] {
			if !loop.Blocks[b.Number] {
				continue
			}
			for n := b.First; n <= b.Last; n++ {
				instructions = append(instructions, n)
				inside[n] = true
				s := g.Instructions[n]
				if x := s.definition(); x != "" {
					definitionCounts[x]++
				}
				if s.Kind == "store" {
					stores[s.Name] = true
				}
				hasCall = hasCall || s.Kind == "call"
			}
		}
		marked := Set[int]{}
		order := []int{}
		for {
			changed := false
			for _, n := range instructions {
				if marked[n] {
					continue
				}
				s := g.Instructions[n]
				if s.Kind != "copy" && s.Kind != "bin" && s.Kind != "load" {
					continue
				}
				if s.Kind == "load" && (hasCall || stores[s.Name]) {
					continue
				}
				invariant := true
				for _, v := range s.used() {
					definitions := []Definition{}
					hasInside := false
					for def := range d.Reaching.Before[n] {
						if def.Variable == v {
							definitions = append(definitions, def)
							hasInside = hasInside || inside[def.Number]
						}
					}
					if hasInside && (len(definitions) != 1 || !marked[definitions[0].Number]) {
						invariant = false
						break
					}
				}
				if invariant {
					marked[n] = true
					order = append(order, n)
					changed = true
				}
			}
			if !changed {
				break
			}
		}
		moves := []int{}
		moved := Set[int]{}
		for _, n := range order {
			s := g.Instructions[n]
			x := s.definition()
			if definitionCounts[x] != 1 || d.LiveIn[loop.Header][x] {
				continue
			}
			block := g.BlockOf[n]
			dominates := true
			for exit := range loop.Exits {
				dominates = dominates && g.Blocks[exit].Dom[block]
			}
			dangerous := s.Kind == "load" || s.Kind == "bin" && (s.Operator == "/" || s.Operator == "%") && (!s.B.IsConstant || s.B.Constant == 0)
			outsideDead := !dangerous
			for outside := range loop.Outside {
				outsideDead = outsideDead && !d.LiveIn[outside][x]
			}
			if !dominates && !outsideDead {
				continue
			}
			dependencies := true
			for _, v := range s.used() {
				for def := range d.Reaching.Before[n] {
					if def.Variable == v && inside[def.Number] && !moved[def.Number] {
						dependencies = false
					}
				}
			}
			if dependencies {
				moves = append(moves, n)
				moved[n] = true
			}
		}
		if len(moves) > 0 {
			destination := hoist(f, g, loop, moves)
			return PassResult{len(moves), []string{fmt.Sprintf("B%d: hoist %s to %s", loop.Header, instructionList(moves), destination)}}
		}
	}
	return PassResult{}
}
func applyPass(name string, f *Function) PassResult {
	g := newCFG(f)
	d := newDataFlow(g)
	switch name {
	case "constprop":
		return constantPropagation(f, g, d)
	case "copyprop":
		return copyPropagation(f, g, d)
	case "cse":
		return commonSubexpressions(f, g, d)
	case "dce":
		return deadCode(f, g, d)
	case "licm":
		return invariantMotion(f, g, d)
	case "unreachable":
		records := removeUnreachable(f, g)
		return PassResult{len(records), records}
	}
	panic("unknown pass")
}
func list(parts []string) string {
	if len(parts) == 0 {
		return "-"
	}
	return strings.Join(parts, ",")
}
func blockList(numbers []int) string {
	parts := []string{}
	for _, n := range numbers {
		parts = append(parts, fmt.Sprintf("B%d", n))
	}
	return list(parts)
}
func instructionList(numbers []int) string {
	parts := []string{}
	for _, n := range numbers {
		parts = append(parts, fmt.Sprintf("#%d", n))
	}
	return list(parts)
}
func definitionList(set Set[Definition]) string {
	definitions := []Definition{}
	for d := range set {
		definitions = append(definitions, d)
	}
	sort.Slice(definitions, func(i, j int) bool {
		if definitions[i].Number != definitions[j].Number {
			return definitions[i].Number < definitions[j].Number
		}
		return definitions[i].Variable < definitions[j].Variable
	})
	parts := []string{}
	for _, d := range definitions {
		parts = append(parts, fmt.Sprintf("%s:%d", d.Variable, d.Number))
	}
	return list(parts)
}
func expressionList(set Set[Expression]) string {
	parts := []string{}
	for e := range set {
		parts = append(parts, e.String())
	}
	sort.Strings(parts)
	return list(parts)
}

type CallGraph struct {
	Callees              map[string][]string
	Reachable, Recursive Set[string]
}

func callGraph(p *Program) *CallGraph {
	graph := &CallGraph{Callees: map[string][]string{}, Reachable: Set[string]{}, Recursive: Set[string]{}}
	for _, f := range p.Functions {
		names := Set[string]{}
		for _, line := range f.Code {
			if s := line.Instruction; s != nil && s.Kind == "call" {
				names[s.Name] = true
			}
		}
		for _, other := range p.Functions {
			if names[other.Name] {
				graph.Callees[f.Name] = append(graph.Callees[f.Name], other.Name)
			}
		}
	}
	var visit func(string, Set[string])
	visit = func(name string, seen Set[string]) {
		if seen[name] {
			return
		}
		seen[name] = true
		for _, next := range graph.Callees[name] {
			visit(next, seen)
		}
	}
	visit("main", graph.Reachable)
	for _, f := range p.Functions {
		seen := Set[string]{}
		for _, next := range graph.Callees[f.Name] {
			visit(next, seen)
		}
		if seen[f.Name] {
			graph.Recursive[f.Name] = true
		}
	}
	return graph
}
func callGraphLines(p *Program, graph *CallGraph) []string {
	out := []string{}
	unreachable := []string{}
	for _, f := range p.Functions {
		line := f.Name + " -> " + list(graph.Callees[f.Name])
		if graph.Recursive[f.Name] {
			line += " (recursive)"
		}
		out = append(out, line)
		if !graph.Reachable[f.Name] {
			unreachable = append(unreachable, f.Name)
		}
	}
	return append(out, "unreachable functions: "+list(unreachable))
}
func analysisLines(f *Function, heading string) []string {
	g := newCFG(f)
	d := newDataFlow(g)
	out := []string{"== " + f.Name + " (" + heading + ") ==", "code:"}
	for _, line := range f.Code {
		if line.Instruction == nil {
			out = append(out, line.Label+":")
			continue
		}
		s := line.Instruction
		text := fmt.Sprintf("  #%d %s", s.Number, s.String())
		if g.Reachable[g.BlockOf[s.Number]] {
			chains := []string{}
			seen := Set[string]{}
			for _, v := range s.used() {
				if seen[v] {
					continue
				}
				seen[v] = true
				numbers := Set[int]{}
				for def := range d.Reaching.Before[s.Number] {
					if def.Variable == v {
						numbers[def.Number] = true
					}
				}
				parts := []string{}
				for _, n := range sortedInts(numbers) {
					parts = append(parts, strconv.Itoa(n))
				}
				chains = append(chains, v+":"+strings.Join(parts, ","))
			}
			if len(chains) > 0 {
				text += " | " + strings.Join(chains, " ")
			}
		}
		out = append(out, text)
	}
	out = append(out, fmt.Sprintf("blocks: %d", len(g.Blocks)-1))
	unreachable := []int{}
	for _, b := range g.Blocks[1:] {
		out = append(out, fmt.Sprintf("B%d %d-%d labels=%s preds=%s succs=%s", b.Number, b.First, b.Last, list(b.Labels), blockList(b.Predecessors), blockList(b.Successors)))
		if !b.Reachable {
			unreachable = append(unreachable, b.Number)
		}
	}
	out = append(out, "unreachable: "+blockList(unreachable), "order: "+blockList(g.ReversePostorder), "dominators:")
	for _, b := range g.Blocks[1:] {
		if !b.Reachable {
			continue
		}
		parent := "-"
		if b.IDom != 0 {
			parent = fmt.Sprintf("B%d", b.IDom)
		}
		out = append(out, fmt.Sprintf("B%d idom=%s dom=%s", b.Number, parent, blockList(sortedInts(b.Dom))))
	}
	out = append(out, "dominator tree:")
	var tree func(int, int)
	tree = func(n, depth int) {
		out = append(out, strings.Repeat(" ", 2*depth)+fmt.Sprintf("B%d", n))
		for _, b := range g.Blocks[1:] {
			if b.Reachable && b.IDom == n {
				tree(b.Number, depth+1)
			}
		}
	}
	tree(1, 0)
	out = append(out, fmt.Sprintf("loops: %d", len(g.Loops)))
	for _, loop := range g.Loops {
		out = append(out, fmt.Sprintf("header=B%d latches=%s depth=%d blocks=%s exits=%s", loop.Header, blockList(loop.Latches), loop.Depth, blockList(sortedInts(loop.Blocks)), blockList(sortedInts(loop.Exits))))
	}
	out = append(out, fmt.Sprintf("reaching definitions: iterations=%d", d.Reaching.Iterations))
	for _, b := range g.Blocks[1:] {
		if b.Reachable {
			out = append(out, fmt.Sprintf("B%d in=%s out=%s", b.Number, definitionList(d.Reaching.In[b.Number]), definitionList(d.Reaching.Out[b.Number])))
		}
	}
	out = append(out, fmt.Sprintf("liveness: iterations=%d", d.LiveIterations))
	for _, b := range g.Blocks[1:] {
		if b.Reachable {
			out = append(out, fmt.Sprintf("B%d in=%s out=%s", b.Number, list(sortedStrings(d.LiveIn[b.Number])), list(sortedStrings(d.LiveOut[b.Number]))))
		}
	}
	out = append(out, fmt.Sprintf("available expressions: iterations=%d", d.Expressions.Iterations))
	for _, b := range g.Blocks[1:] {
		if b.Reachable {
			out = append(out, fmt.Sprintf("B%d in=%s out=%s", b.Number, expressionList(d.Expressions.In[b.Number]), expressionList(d.Expressions.Out[b.Number])))
		}
	}
	return out
}
func allocatedFunction(f *Function, a *Allocation) (*Function, int) {
	out := cloneFunction(f)
	rename := func(name string) string {
		if r, ok := a.Registers[name]; ok {
			return fmt.Sprintf("R%d", r)
		}
		return name
	}
	for i, p := range out.Parameters {
		out.Parameters[i] = rename(p)
	}
	code := []CodeLine{}
	removed := 0
	for _, line := range out.Code {
		s := line.Instruction
		if s != nil {
			if s.Destination != "" {
				s.Destination = rename(s.Destination)
			}
			for _, operand := range s.operands() {
				if !operand.IsConstant {
					operand.Variable = rename(operand.Variable)
				}
			}
			if s.Kind == "copy" && !s.A.IsConstant && s.Destination == s.A.Variable {
				removed++
				continue
			}
		}
		code = append(code, line)
	}
	out.Code = code
	return out, removed
}
func allocationLines(f *Function, k int) (*Function, []string) {
	g := newCFG(f)
	d := newDataFlow(g)
	a := allocate(g, d, k)
	out := []string{"== " + f.Name + " ==", fmt.Sprintf("nodes=%d edges=%d registers=%d", len(a.Nodes), a.Edges, k)}
	for _, v := range a.Nodes {
		out = append(out, fmt.Sprintf("%s degree=%d cost=%s neighbors=%s", v, len(a.Neighbors[v]), a.Costs[v].String(), list(sortedStrings(a.Neighbors[v]))))
	}
	potential := []string{}
	for _, p := range a.Potential {
		potential = append(potential, fmt.Sprintf("%s(%s/%d)", p.Name, a.Costs[p.Name].String(), p.Degree))
	}
	out = append(out, "simplify: "+list(a.Simplify), "potential spills: "+list(potential))
	used := Set[int]{}
	for _, v := range a.Nodes {
		target := "spill"
		if r, ok := a.Registers[v]; ok {
			target = fmt.Sprintf("R%d", r)
			used[r] = true
		}
		out = append(out, v+" -> "+target)
	}
	pressure := 0
	for n := range d.LiveBefore {
		pressure = max(pressure, len(d.LiveBefore[n]), len(d.LiveAfter[n]))
	}
	spillUses, spillDefs := 0, 0
	for _, p := range f.Parameters {
		if a.Spills[p] {
			spillDefs++
		}
	}
	for _, line := range f.Code {
		if s := line.Instruction; s != nil {
			if a.Spills[s.Destination] {
				spillDefs++
			}
			for _, v := range s.used() {
				if a.Spills[v] {
					spillUses++
				}
			}
		}
	}
	allocated, moves := allocatedFunction(f, a)
	out = append(out, fmt.Sprintf("summary: pressure=%d used=%d spilled=%d moves=%d spill_uses=%d spill_defs=%d", pressure, len(used), len(a.Spills), moves, spillUses, spillDefs))
	return allocated, append(out, functionLines(allocated)...)
}

type Execution struct {
	Steps, Calls map[string]int64
	Kinds        map[string]int64
	Output       []int64
}
type Interpreter struct {
	Functions  map[string]*Function
	Arrays     map[string][]int64
	Input      []int64
	InputIndex int
	Result     Execution
}

func executeProgram(p *Program, input []int64) Execution {
	vm := &Interpreter{Functions: map[string]*Function{}, Arrays: map[string][]int64{}, Input: input, Result: Execution{Steps: map[string]int64{}, Calls: map[string]int64{}, Kinds: map[string]int64{}}}
	for _, f := range p.Functions {
		vm.Functions[f.Name] = f
	}
	for _, array := range p.Arrays {
		vm.Arrays[array.Name] = make([]int64, array.Size)
	}
	vm.call("main", nil)
	return vm.Result
}
func (vm *Interpreter) call(name string, args []int64) int64 {
	f := vm.Functions[name]
	variables := map[string]int64{}
	for i, p := range f.Parameters {
		variables[p] = args[i]
	}
	labels := map[string]int{}
	for i, line := range f.Code {
		if line.Instruction == nil {
			labels[line.Label] = i + 1
		}
	}
	value := func(a Operand) int64 {
		if a.IsConstant {
			return a.Constant
		}
		return variables[a.Variable]
	}
	pushed := []int64{}
	vm.Result.Calls[name]++
	for pc := 0; pc < len(f.Code); {
		s := f.Code[pc].Instruction
		pc++
		if s == nil {
			continue
		}
		vm.Result.Steps[name]++
		vm.Result.Kinds[s.Kind]++
		switch s.Kind {
		case "copy":
			variables[s.Destination] = value(s.A)
		case "bin":
			variables[s.Destination] = calculate(s.Operator, value(s.A), value(s.B))
		case "load":
			variables[s.Destination] = vm.Arrays[s.Name][int(value(s.A))]
		case "store":
			index := int(value(s.A))
			vm.Arrays[s.Name][index] = value(s.B)
		case "goto":
			pc = labels[s.Name]
		case "if":
			if calculate(s.Operator, value(s.A), value(s.B)) != 0 {
				pc = labels[s.Name]
			}
		case "param":
			pushed = append(pushed, value(s.A))
		case "call":
			start := len(pushed) - s.Count
			arguments := append([]int64{}, pushed[start:]...)
			pushed = pushed[:start]
			returned := vm.call(s.Name, arguments)
			if s.Destination != "" {
				variables[s.Destination] = returned
			}
		case "return":
			if s.HasA {
				return value(s.A)
			}
			return 0
		case "read":
			variables[s.Destination] = vm.Input[vm.InputIndex]
			vm.InputIndex++
		case "print":
			vm.Result.Output = append(vm.Result.Output, value(s.A))
		}
	}
	return 0
}
func total(values map[string]int64) int64 {
	sum := int64(0)
	for _, v := range values {
		sum += v
	}
	return sum
}
func instructionCounts(p *Program) map[string]int64 {
	counts := map[string]int64{}
	for _, f := range p.Functions {
		for _, line := range f.Code {
			if line.Instruction != nil {
				counts[line.Instruction.Kind]++
			}
		}
	}
	return counts
}
func outputList(values []int64) string {
	parts := []string{}
	for _, v := range values {
		parts = append(parts, strconv.FormatInt(v, 10))
	}
	return list(parts)
}
func sameOutput(a, b []int64) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
func comparisons(original, optimized, allocated *Program, runs [][]int64) []string {
	programs := []*Program{original, optimized, allocated}
	names := []string{"original", "optimized", "allocated"}
	aggregates := []Execution{}
	for range programs {
		aggregates = append(aggregates, Execution{Steps: map[string]int64{}, Calls: map[string]int64{}, Kinds: map[string]int64{}})
	}
	out := []string{}
	same := 0
	for i, input := range runs {
		out = append(out, fmt.Sprintf("run %d: inputs=%d", i+1, len(input)))
		results := []Execution{}
		for j, p := range programs {
			result := executeProgram(p, input)
			results = append(results, result)
			out = append(out, fmt.Sprintf("  %s: steps=%d calls=%d output=%s", names[j], total(result.Steps), total(result.Calls), outputList(result.Output)))
			for f, n := range result.Steps {
				aggregates[j].Steps[f] += n
			}
			for f, n := range result.Calls {
				aggregates[j].Calls[f] += n
			}
			for kind, n := range result.Kinds {
				aggregates[j].Kinds[kind] += n
			}
		}
		result := "different"
		if sameOutput(results[0].Output, results[1].Output) && sameOutput(results[0].Output, results[2].Output) {
			result = "same"
			same++
		}
		out = append(out, "  result: "+result)
	}
	out = append(out, "== profile ==")
	for _, f := range original.Functions {
		out = append(out, fmt.Sprintf("%s: calls=%d original=%d optimized=%d allocated=%d", f.Name, aggregates[0].Calls[f.Name], aggregates[0].Steps[f.Name], aggregates[1].Steps[f.Name], aggregates[2].Steps[f.Name]))
	}
	before, after := instructionCounts(original), instructionCounts(optimized)
	out = append(out, "== summary ==", fmt.Sprintf("runs=%d same=%d different=%d", len(runs), same, len(runs)-same), fmt.Sprintf("instructions: original=%d optimized=%d", total(before), total(after)))
	parts := []string{}
	for _, kind := range instructionKinds {
		parts = append(parts, fmt.Sprintf("%s=%d->%d", kind, before[kind], after[kind]))
	}
	out = append(out, "kinds: "+strings.Join(parts, " "), fmt.Sprintf("steps: original=%d optimized=%d allocated=%d", total(aggregates[0].Steps), total(aggregates[1].Steps), total(aggregates[2].Steps)))
	for j, name := range names {
		parts = nil
		for _, kind := range instructionKinds {
			parts = append(parts, fmt.Sprintf("%s=%d", kind, aggregates[j].Kinds[kind]))
		}
		out = append(out, "dynamic "+name+": "+strings.Join(parts, " "))
	}
	return out
}
func save(name string, lines []string) {
	if err := os.WriteFile("output/"+name, []byte(strings.Join(lines, "\n")+"\n"), 0644); err != nil {
		panic(err)
	}
}
func main() {
	original := parseProgram()
	optimized := cloneProgram(original)
	parameters := readLines("input/params.txt")
	registers := int(integer(strings.Fields(parameters[0])[1]))
	enabled := Set[string]{}
	for _, name := range strings.Fields(parameters[1])[1:] {
		enabled[name] = true
	}
	maxRounds := int(integer(strings.Fields(parameters[2])[1]))
	passes := []string{}
	for _, name := range passOrder {
		if enabled[name] {
			passes = append(passes, name)
		}
	}
	analysis := append([]string{"== call graph (original) =="}, callGraphLines(original, callGraph(original))...)
	for _, f := range original.Functions {
		analysis = append(analysis, analysisLines(f, "original")...)
	}
	passLines := []string{}
	totals := map[string]int{}
	for _, f := range optimized.Functions {
		before := len(newCFG(f).Instructions) - 1
		passLines = append(passLines, "== "+f.Name+" ==")
		rounds := 0
		for round := 1; round <= maxRounds; round++ {
			rounds = round
			parts := []string{}
			records := []string{}
			changed := 0
			for _, name := range passes {
				result := applyPass(name, f)
				parts = append(parts, fmt.Sprintf("%s=%d", name, result.Count))
				changed += result.Count
				totals[name] += result.Count
				for _, record := range result.Records {
					records = append(records, "  "+name+" "+record)
				}
			}
			passLines = append(passLines, fmt.Sprintf("round %d: %s", round, strings.Join(parts, " ")))
			passLines = append(passLines, records...)
			if changed == 0 {
				break
			}
		}
		passLines = append(passLines, fmt.Sprintf("result: rounds=%d instructions=%d->%d", rounds, before, len(newCFG(f).Instructions)-1))
	}
	graph := callGraph(optimized)
	analysis = append(analysis, "== call graph (optimized) ==")
	analysis = append(analysis, callGraphLines(optimized, graph)...)
	removed := []string{}
	kept := []*Function{}
	for _, f := range optimized.Functions {
		if enabled["unreachable"] && !graph.Reachable[f.Name] {
			removed = append(removed, f.Name)
		} else {
			kept = append(kept, f)
		}
	}
	optimized.Functions = kept
	for _, f := range optimized.Functions {
		analysis = append(analysis, analysisLines(f, "optimized")...)
	}
	passLines = append(passLines, "== program ==", "removed functions: "+list(removed), "== total ==")
	parts := []string{}
	for _, name := range passes {
		parts = append(parts, fmt.Sprintf("%s=%d", name, totals[name]))
	}
	passLines = append(passLines, strings.Join(parts, " "))
	allocated := &Program{Arrays: append([]Array{}, optimized.Arrays...)}
	allocation := []string{}
	for _, f := range optimized.Functions {
		result, lines := allocationLines(f, registers)
		allocated.Functions = append(allocated.Functions, result)
		allocation = append(allocation, lines...)
	}
	inputs := readLines("input/input.txt")
	runs := [][]int64{}
	for _, line := range inputs[1 : int(integer(inputs[0]))+1] {
		words := strings.Fields(line)
		run := []int64{}
		for _, word := range words[1:] {
			run = append(run, integer(word))
		}
		runs = append(runs, run)
	}
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	save("optimized.tac", programLines(optimized))
	save("analysis.txt", analysis)
	save("passes.txt", passLines)
	save("regalloc.txt", allocation)
	save("comparison.txt", comparisons(original, optimized, allocated, runs))
}
