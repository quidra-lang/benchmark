package main

import (
	"fmt"
	"sort"
	"strings"
)

var specialNames = []string{"FILENAME", "FNR", "FS", "NF", "NR", "OFS", "ORS", "SUBSEP"}

type StaticIssue struct {
	Position Position
	Priority int
	Message  string
}
type Analysis struct {
	Items, Functions, Rules []*Item
	FunctionTable           map[string]*Item
	Globals                 map[string]bool
	Arrays                  map[Binding]bool
	Expressions             []*Expr
	Statements              []*Statement
	Lines                   map[int]bool
	Errors                  []StaticIssue
}

func newAnalysis(items []*Item) *Analysis {
	a := &Analysis{Items: items, FunctionTable: map[string]*Item{}, Globals: map[string]bool{}, Arrays: map[Binding]bool{}, Lines: map[int]bool{}}
	for _, name := range specialNames {
		a.Globals[name] = true
	}
	for _, item := range items {
		if item.Kind == "function" {
			a.Functions = append(a.Functions, item)
		} else {
			a.Rules = append(a.Rules, item)
		}
	}
	return a
}
func (a *Analysis) issue(position Position, priority int, message string) {
	a.Errors = append(a.Errors, StaticIssue{position, priority, message})
}
func (a *Analysis) expression(e *Expr, function *Item) {
	if e == nil {
		return
	}
	a.Expressions = append(a.Expressions, e)
	if e.Kind == "name" || e.Kind == "array" || e.Kind == "parameter" {
		e.Binding = Binding{Name: e.Name}
		if function != nil && function.ParameterNames[e.Name] {
			e.Binding.Function = function
		} else {
			a.Globals[e.Name] = true
		}
		if a.FunctionTable[e.Name] != nil {
			a.issue(e.Position, 2, "function "+e.Name+" used as variable")
		}
	} else if e.Kind == "call" {
		e.Function = a.FunctionTable[e.Name]
		if e.Function == nil {
			a.issue(e.Position, 3, "undefined function "+e.Name)
		} else if len(e.Args) > len(e.Function.Parameters) {
			a.issue(e.Position, 4, "too many arguments to "+e.Name)
		}
	}
	a.expression(e.Left, function)
	a.expression(e.Right, function)
	a.expression(e.Third, function)
	for _, argument := range e.Args {
		a.expression(argument, function)
	}
}
func (a *Analysis) statement(s *Statement, function *Item) {
	if s == nil {
		return
	}
	a.Statements = append(a.Statements, s)
	if s.Kind != "block" && s.Kind != "empty" {
		a.Lines[s.Position.Line] = true
	}
	for _, e := range s.Exprs {
		a.expression(e, function)
	}
	a.expression(s.Variable, function)
	a.expression(s.Array, function)
	a.expression(s.Redirect, function)
	for _, child := range s.Statements {
		a.statement(child, function)
	}
	a.statement(s.Body, function)
	a.statement(s.Else, function)
}
func (a *Analysis) prepare() {
	for _, function := range a.Functions {
		if a.FunctionTable[function.Name] != nil {
			a.issue(function.NamePosition, 0, "function "+function.Name+" redefined")
		} else {
			a.FunctionTable[function.Name] = function
		}
		function.ParameterNames = map[string]bool{}
		for _, parameter := range function.Parameters {
			if function.ParameterNames[parameter.Name] {
				a.issue(parameter.Position, 1, "duplicate parameter "+parameter.Name)
			}
			function.ParameterNames[parameter.Name] = true
		}
	}
	for _, item := range a.Items {
		var function *Item
		if item.Kind == "function" {
			function = item
		}
		for _, parameter := range item.Parameters {
			a.expression(parameter, function)
		}
		for _, pattern := range item.Patterns {
			a.expression(pattern, function)
		}
		a.statement(item.Body, function)
	}
	if len(a.Errors) > 0 {
		sort.SliceStable(a.Errors, func(i, j int) bool {
			x, y := a.Errors[i], a.Errors[j]
			if x.Position.Line != y.Position.Line {
				return x.Position.Line < y.Position.Line
			}
			if x.Position.Column != y.Position.Column {
				return x.Position.Column < y.Position.Column
			}
			return x.Priority < y.Priority
		})
		panic(a.Errors[0])
	}
	links := [][2]Binding{}
	for _, e := range a.Expressions {
		switch e.Kind {
		case "array":
			a.Arrays[e.Binding] = true
		case "membership":
			a.Arrays[e.Right.Binding] = true
		case "builtin":
			if e.Name == "split" {
				a.Arrays[e.Args[1].Binding] = true
			}
		case "call":
			for i, argument := range e.Args {
				if argument.Kind == "name" {
					links = append(links, [2]Binding{argument.Binding, e.Function.Parameters[i].Binding})
				}
			}
		}
	}
	for _, s := range a.Statements {
		if s.Kind == "delete" || s.Kind == "for_in" {
			a.Arrays[s.Array.Binding] = true
		}
	}
	for {
		changed := false
		for _, link := range links {
			if a.Arrays[link[0]] && !a.Arrays[link[1]] {
				a.Arrays[link[1]] = true
				changed = true
			}
			if a.Arrays[link[1]] && !a.Arrays[link[0]] {
				a.Arrays[link[0]] = true
				changed = true
			}
		}
		if !changed {
			break
		}
	}
}

type Cell struct {
	Value Value
	Array map[string]Value
}
type Location struct {
	Kind  string
	Cell  *Cell
	Key   string
	Index int
	NF    bool
}
type Transfer struct {
	Kind  string
	Value Value
}

func trap(action func()) (transfer *Transfer) {
	defer func() {
		if failure := recover(); failure != nil {
			if t, ok := failure.(Transfer); ok {
				transfer = &t
			} else {
				panic(failure)
			}
		}
	}()
	action()
	return nil
}
func arithmetic(op string, a, b Value, position Position) Value {
	x, y := a.number(), b.number()
	var result int64
	switch op {
	case "+":
		result = x + y
	case "-":
		result = x - y
	case "*":
		result = x * y
	case "/", "%":
		if y == 0 {
			runtimeError(position, "division by zero")
		}
		result = x / y
		if op == "%" {
			result = x - result*y
		}
	case "^":
		if y < 0 {
			runtimeError(position, "negative exponent")
		}
		result = 1
		for y > 0 {
			if y&1 != 0 {
				result *= x
			}
			y >>= 1
			if y > 0 {
				x *= x
			}
		}
	}
	return numeric(result)
}

type Engine struct {
	Analysis                 *Analysis
	Options                  []Option
	Operands                 []*Operand
	Globals                  map[string]*Cell
	Locals                   []map[string]*Cell
	Record                   *Record
	Streams                  *Streams
	Lines                    map[int]int
	Phase                    string
	ExitStatus               int64
	Error                    *RuntimeIssue
	OperandIndex, InputIndex int
	Current                  *Operand
	InputLines               []string
}

func newEngine(a *Analysis, options []Option, operands []*Operand) *Engine {
	e := &Engine{Analysis: a, Options: options, Operands: operands, Globals: map[string]*Cell{}, Streams: newStreams(), Lines: map[int]int{}, Phase: "BEGIN"}
	for name := range a.Globals {
		cell := &Cell{}
		if a.Arrays[Binding{Name: name}] {
			cell.Array = map[string]Value{}
		}
		e.Globals[name] = cell
	}
	for _, name := range specialNames {
		e.Globals[name].Value = numeric(0)
	}
	e.Globals["FILENAME"].Value = stringValue("")
	e.Globals["FS"].Value = stringValue(" ")
	e.Globals["OFS"].Value = stringValue(" ")
	e.Globals["ORS"].Value = stringValue("\n")
	e.Globals["SUBSEP"].Value = stringValue(string(byte(28)))
	for line := range a.Lines {
		e.Lines[line] = 0
	}
	e.Record = &Record{Zero: stringValue(""), Global: e.global}
	return e
}
func (e *Engine) cell(binding Binding) *Cell {
	if binding.Function != nil {
		return e.Locals[len(e.Locals)-1][binding.Name]
	}
	return e.Globals[binding.Name]
}
func (e *Engine) global(name string) Value {
	if name == "NF" {
		return numeric(int64(len(e.Record.Fields)))
	}
	return e.Globals[name].Value
}
func (e *Engine) assignInput(name, text string) {
	cell := e.Globals[name]
	if cell == nil {
		cell = &Cell{}
		e.Globals[name] = cell
	}
	cell.Value = inputValue(text)
}
func (e *Engine) subscript(args []*Expr) string {
	values := []string{}
	for _, arg := range args {
		values = append(values, e.evaluate(arg).text())
	}
	return strings.Join(values, e.global("SUBSEP").text())
}
func (e *Engine) location(node *Expr) Location {
	switch node.Kind {
	case "name":
		return Location{Kind: "variable", Cell: e.cell(node.Binding), NF: node.Binding.Function == nil && node.Name == "NF"}
	case "array":
		key := e.subscript(node.Args)
		return Location{Kind: "array", Cell: e.cell(node.Binding), Key: key}
	}
	index := e.evaluate(node.Left).number()
	if index < 0 {
		runtimeError(node.Position, "negative field index")
	}
	return Location{Kind: "field", Index: int(index)}
}
func (e *Engine) read(location Location) Value {
	switch location.Kind {
	case "field":
		return e.Record.read(location.Index)
	case "array":
		value, exists := location.Cell.Array[location.Key]
		if !exists {
			location.Cell.Array[location.Key] = Value{}
		}
		return value
	}
	if location.NF {
		return numeric(int64(len(e.Record.Fields)))
	}
	return location.Cell.Value
}
func (e *Engine) store(location Location, value Value, position Position) {
	switch location.Kind {
	case "field":
		e.Record.write(location.Index, value)
	case "array":
		location.Cell.Array[location.Key] = value
	default:
		if location.NF {
			n := value.number()
			if n < 0 {
				runtimeError(position, "negative NF")
			}
			e.Record.resize(int(n))
		} else {
			location.Cell.Value = value
		}
	}
}
func (e *Engine) evaluate(node *Expr) Value {
	switch node.Kind {
	case "number", "string":
		return node.Value
	case "name", "array", "field":
		return e.read(e.location(node))
	case "paren":
		return e.evaluate(node.Left)
	case "assignment":
		location := e.location(node.Left)
		value := e.evaluate(node.Right)
		if node.Op != "=" {
			value = arithmetic(node.Op[:1], e.read(location), value, node.Position)
		}
		e.store(location, value, node.Position)
		return e.read(location)
	case "increment":
		location := e.location(node.Left)
		old := e.read(location).number()
		value := old + 1
		if node.Op == "--" {
			value = old - 1
		}
		e.store(location, numeric(value), node.Position)
		if node.Prefix {
			return numeric(value)
		}
		return numeric(old)
	case "conditional":
		if e.evaluate(node.Left).truth() {
			return e.evaluate(node.Right)
		}
		return e.evaluate(node.Third)
	case "unary":
		value := e.evaluate(node.Left)
		if node.Op == "!" {
			return boolean(!value.truth())
		}
		n := value.number()
		if node.Op == "-" {
			n = -n
		}
		return numeric(n)
	case "membership":
		key := e.subscript(node.Args)
		_, exists := e.cell(node.Right.Binding).Array[key]
		return boolean(exists)
	case "binary":
		first := e.evaluate(node.Left)
		if node.Op == "||" && first.truth() {
			return numeric(1)
		}
		if node.Op == "&&" && !first.truth() {
			return numeric(0)
		}
		second := e.evaluate(node.Right)
		if node.Op == "&&" || node.Op == "||" {
			return boolean(second.truth())
		}
		if node.Op == "concat" {
			return stringValue(first.text() + second.text())
		}
		if wordIn("< <= == != >= >", node.Op) {
			order := compare(first, second)
			result := false
			switch node.Op {
			case "<":
				result = order < 0
			case "<=":
				result = order <= 0
			case "==":
				result = order == 0
			case "!=":
				result = order != 0
			case ">=":
				result = order >= 0
			case ">":
				result = order > 0
			}
			return boolean(result)
		}
		return arithmetic(node.Op, first, second, node.Position)
	case "call":
		return e.call(node)
	case "builtin":
		return e.builtin(node)
	case "getline":
		return e.getline(node)
	}
	panic("unknown expression")
}
func boolean(value bool) Value {
	if value {
		return numeric(1)
	}
	return numeric(0)
}
func (e *Engine) call(node *Expr) Value {
	function := node.Function
	locals := map[string]*Cell{}
	for i, parameter := range function.Parameters {
		if e.Analysis.Arrays[parameter.Binding] {
			if i < len(node.Args) {
				locals[parameter.Name] = e.cell(node.Args[i].Binding)
			} else {
				locals[parameter.Name] = &Cell{Array: map[string]Value{}}
			}
		} else {
			value := Value{}
			if i < len(node.Args) {
				value = e.evaluate(node.Args[i])
			}
			locals[parameter.Name] = &Cell{Value: value}
		}
	}
	function.Calls++
	function.Active++
	function.Depth = max(function.Depth, function.Active)
	e.Locals = append(e.Locals, locals)
	defer func() {
		e.Locals = e.Locals[:len(e.Locals)-1]
		function.Active--
	}()
	transfer := trap(func() { e.statement(function.Body) })
	if transfer != nil {
		if transfer.Kind == "return" {
			return transfer.Value
		}
		panic(*transfer)
	}
	return Value{}
}
func (e *Engine) builtin(node *Expr) Value {
	switch node.Name {
	case "length":
		if len(node.Args) == 0 {
			return numeric(int64(len(e.Record.Zero.text())))
		}
		arg := node.Args[0]
		if arg.Kind == "name" && e.Analysis.Arrays[arg.Binding] {
			return numeric(int64(len(e.cell(arg.Binding).Array)))
		}
		return numeric(int64(len(e.evaluate(arg).text())))
	case "split":
		text := e.evaluate(node.Args[0]).text()
		separator := ""
		if len(node.Args) == 3 {
			separator = e.evaluate(node.Args[2]).text()
		} else {
			separator = e.global("FS").text()
		}
		array := e.cell(node.Args[1].Binding).Array
		clear(array)
		pieces := splitPieces(text, separator)
		for i, piece := range pieces {
			array[fmt.Sprint(i+1)] = inputValue(piece)
		}
		return numeric(int64(len(pieces)))
	case "close":
		return numeric(e.Streams.close(e.evaluate(node.Args[0]).text()))
	}
	values := []Value{}
	for _, arg := range node.Args {
		values = append(values, e.evaluate(arg))
	}
	return invokeBuiltin(node.Name, values, node.Position)
}
func (e *Engine) getline(node *Expr) Value {
	status, line := 0, ""
	if node.Right != nil {
		name := e.evaluate(node.Right).text()
		status, line = e.Streams.getline(name)
	} else if e.Phase != "END" {
		var found bool
		line, found = e.nextRecord()
		if found {
			status = 1
		}
	}
	if status == 1 {
		if node.Left == nil {
			e.Record.set(line)
		} else {
			location := e.location(node.Left)
			e.store(location, inputValue(line), node.Position)
		}
	}
	return numeric(int64(status))
}
func (e *Engine) output(node *Statement) {
	values := []Value{}
	for _, arg := range node.Exprs {
		values = append(values, e.evaluate(arg))
	}
	text := ""
	if node.Kind == "print" {
		if len(values) == 0 {
			values = append(values, e.Record.Zero)
		}
		parts := []string{}
		for _, value := range values {
			parts = append(parts, value.text())
		}
		text = strings.Join(parts, e.global("OFS").text()) + e.global("ORS").text()
	} else {
		text = formatOutput(values, node.Position)
	}
	name := ""
	if node.Redirect != nil {
		name = e.evaluate(node.Redirect).text()
	}
	e.Streams.write(text, name, node.RedirectMode, node.RedirectPosition)
}
func (e *Engine) loopBody(body *Statement) bool {
	transfer := trap(func() { e.statement(body) })
	if transfer == nil {
		return true
	}
	if transfer.Kind == "break" {
		return false
	}
	if transfer.Kind == "continue" {
		return true
	}
	panic(*transfer)
}
func (e *Engine) statement(node *Statement) {
	if node.Kind == "block" {
		for _, child := range node.Statements {
			e.statement(child)
		}
		return
	}
	if node.Kind == "empty" {
		return
	}
	e.Lines[node.Position.Line]++
	switch node.Kind {
	case "expression":
		e.evaluate(node.Exprs[0])
	case "print", "printf":
		e.output(node)
	case "if":
		if e.evaluate(node.Exprs[0]).truth() {
			e.statement(node.Body)
		} else if node.Else != nil {
			e.statement(node.Else)
		}
	case "while":
		for e.evaluate(node.Exprs[0]).truth() {
			if !e.loopBody(node.Body) {
				break
			}
		}
	case "do":
		for {
			if !e.loopBody(node.Body) || !e.evaluate(node.Exprs[0]).truth() {
				break
			}
		}
	case "for":
		if node.Exprs[0] != nil {
			e.evaluate(node.Exprs[0])
		}
		for node.Exprs[1] == nil || e.evaluate(node.Exprs[1]).truth() {
			if !e.loopBody(node.Body) {
				break
			}
			if node.Exprs[2] != nil {
				e.evaluate(node.Exprs[2])
			}
		}
	case "for_in":
		keys := orderedSubscripts(e.cell(node.Array.Binding).Array)
		for _, key := range keys {
			location := e.location(node.Variable)
			e.store(location, inputValue(key), node.Variable.Position)
			if !e.loopBody(node.Body) {
				break
			}
		}
	case "delete":
		array := e.cell(node.Array.Binding).Array
		if node.WholeDelete {
			clear(array)
		} else {
			key := e.subscript(node.Exprs)
			delete(array, key)
		}
	case "next":
		if e.Phase == "BEGIN" || e.Phase == "END" {
			runtimeError(node.Position, "next used in BEGIN or END")
		}
		panic(Transfer{Kind: "next"})
	case "exit":
		if len(node.Exprs) > 0 {
			e.ExitStatus = e.evaluate(node.Exprs[0]).number()
		}
		panic(Transfer{Kind: "exit"})
	case "return":
		value := Value{}
		if len(node.Exprs) > 0 {
			value = e.evaluate(node.Exprs[0])
		}
		panic(Transfer{Kind: "return", Value: value})
	case "break", "continue":
		panic(Transfer{Kind: node.Kind})
	}
}
func (e *Engine) nextRecord() (string, bool) {
	for {
		if e.InputIndex < len(e.InputLines) {
			line := e.InputLines[e.InputIndex]
			e.InputIndex++
			e.Current.Records++
			e.Globals["NR"].Value = numeric(e.global("NR").number() + 1)
			e.Globals["FNR"].Value = numeric(e.global("FNR").number() + 1)
			return line, true
		}
		if e.OperandIndex == len(e.Operands) {
			return "", false
		}
		operand := e.Operands[e.OperandIndex]
		e.OperandIndex++
		if operand.Kind == "assignment" {
			e.assignInput(operand.Name, operand.Value)
		} else {
			e.Current = operand
			e.InputLines = readRecords(operand.Name)
			e.InputIndex = 0
			e.Globals["FILENAME"].Value = stringValue(operand.Name)
			e.Globals["FNR"].Value = numeric(0)
		}
	}
}
func (e *Engine) actions(phase string) {
	e.Phase = phase
	for _, rule := range e.Analysis.Rules {
		if rule.Flavor == phase {
			rule.Count++
			e.statement(rule.Body)
		}
	}
}
func (e *Engine) matches(rule *Item) bool {
	if rule.Flavor == "all" {
		return true
	}
	if rule.Flavor == "pattern" {
		return e.evaluate(rule.Patterns[0]).truth()
	}
	if !rule.Inside && e.evaluate(rule.Patterns[0]).truth() {
		rule.Inside = true
	}
	if !rule.Inside {
		return false
	}
	if e.evaluate(rule.Patterns[1]).truth() {
		rule.Inside = false
	}
	return true
}
func (e *Engine) records() {
	any := false
	for _, rule := range e.Analysis.Rules {
		any = any || rule.Flavor != "BEGIN"
	}
	if !any {
		return
	}
	e.Phase = "records"
	for {
		line, found := e.nextRecord()
		if !found {
			return
		}
		e.Record.set(line)
		transfer := trap(func() {
			for _, rule := range e.Analysis.Rules {
				if rule.Flavor == "BEGIN" || rule.Flavor == "END" {
					continue
				}
				if e.matches(rule) {
					rule.Count++
					if rule.Body == nil {
						e.Streams.write(e.Record.Zero.text()+e.global("ORS").text(), "", "", Position{})
					} else {
						e.statement(rule.Body)
					}
				}
			}
		})
		if transfer != nil && transfer.Kind != "next" {
			panic(*transfer)
		}
	}
}
func (e *Engine) execute() {
	defer func() {
		if failure := recover(); failure != nil {
			if issue, ok := failure.(RuntimeIssue); ok {
				e.Error = &issue
			} else {
				panic(failure)
			}
		}
	}()
	for _, option := range e.Options {
		e.assignInput(option.Name, option.Value)
	}
	transfer := trap(func() {
		e.actions("BEGIN")
		e.records()
	})
	if transfer != nil && transfer.Kind != "exit" {
		panic(*transfer)
	}
	transfer = trap(func() { e.actions("END") })
	if transfer != nil && transfer.Kind != "exit" {
		panic(*transfer)
	}
}
func (e *Engine) statistics() []string {
	status := fmt.Sprintf("status: exit %d", e.ExitStatus)
	if e.Error != nil {
		status = "status: runtime error at " + e.Error.Position.String() + ": " + e.Error.Message
	}
	out := []string{status, "[inputs]"}
	for _, operand := range e.Operands {
		if operand.Kind == "file" {
			out = append(out, fmt.Sprintf("%s records=%d", operand.Name, operand.Records))
		}
	}
	out = append(out, "[getline]")
	for _, name := range e.Streams.InputOrder {
		source := e.Streams.Inputs[name]
		suffix := "missing"
		if source.EverOpened {
			suffix = fmt.Sprintf("reads=%d", source.Reads)
		}
		out = append(out, name+" "+suffix)
	}
	out = append(out, "[rules]")
	for _, rule := range e.Analysis.Rules {
		out = append(out, fmt.Sprintf("%s %s count=%d", rule.Position.String(), rule.Flavor, rule.Count))
	}
	out = append(out, "[functions]")
	for _, function := range e.Analysis.Functions {
		out = append(out, fmt.Sprintf("%s calls=%d depth=%d", function.Name, function.Calls, function.Depth))
	}
	out = append(out, "[outputs]", fmt.Sprintf("stdout.txt writes=%d bytes=%d", e.Streams.Stdout.Writes, len(e.Streams.Stdout.content())))
	for _, name := range e.Streams.OutputOrder {
		stream := e.Streams.Outputs[name]
		out = append(out, fmt.Sprintf("%s writes=%d bytes=%d", name, stream.Writes, len(stream.content())))
	}
	lineNumbers := []int{}
	for line := range e.Lines {
		lineNumbers = append(lineNumbers, line)
	}
	sort.Ints(lineNumbers)
	out = append(out, "[lines]")
	for _, line := range lineNumbers {
		out = append(out, fmt.Sprintf("%d count=%d", line, e.Lines[line]))
	}
	globalNames := []string{}
	for name := range e.Globals {
		globalNames = append(globalNames, name)
	}
	sort.Strings(globalNames)
	out = append(out, "[globals]")
	for _, name := range globalNames {
		text := describe(e.global(name))
		if e.Analysis.Arrays[Binding{Name: name}] {
			text = fmt.Sprintf("array (%d)", len(e.Globals[name].Array))
		}
		out = append(out, name+" = "+text)
	}
	return out
}
func process(options []Option, operands []*Operand, source string) (streams *Streams, statistics []string) {
	streams = newStreams()
	defer func() {
		if failure := recover(); failure != nil {
			switch issue := failure.(type) {
			case SyntaxIssue:
				statistics = []string{"status: syntax error at " + issue.Position.String()}
			case StaticIssue:
				statistics = []string{"status: error at " + issue.Position.String() + ": " + issue.Message}
			default:
				panic(failure)
			}
		}
	}()
	parser := Parser{Tokens: tokenize(source)}
	analysis := newAnalysis(parser.parse())
	analysis.prepare()
	engine := newEngine(analysis, options, operands)
	engine.execute()
	return engine.Streams, engine.statistics()
}
func main() {
	options, operands := parseArguments(textLines(readText("input/args.txt")))
	streams, statistics := process(options, operands, readText("input/program.awk"))
	streams.save()
	writeFile("output/stats.txt", strings.Join(statistics, "\n")+"\n")
}
