package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

type TypePrinter struct {
	Names      map[*Type]string
	Quantified map[*Type]bool
	Local      bool
}

func (p *TypePrinter) print(t *Type) string {
	t = resolve(t)
	if t.Kind == "var" {
		if p.Names == nil {
			p.Names = map[*Type]string{}
		}
		if name, ok := p.Names[t]; ok {
			return name
		}
		index := len(p.Names)
		prefix := "'"
		if p.Local && !p.Quantified[t] {
			prefix = "'_"
		}
		name := prefix + string(rune('a'+index%26))
		if index >= 26 {
			name += strconv.Itoa(index / 26)
		}
		p.Names[t] = name
		return name
	}
	if wordIn("int bool string", t.Kind) {
		return t.Kind
	}
	first := resolve(t.Children[0])
	left := p.print(first)
	if t.Kind == "list" {
		if first.Kind == "pair" || first.Kind == "function" {
			left = "(" + left + ")"
		}
		return left + " list"
	}
	second := resolve(t.Children[1])
	right := p.print(second)
	if t.Kind == "pair" {
		if first.Kind == "pair" || first.Kind == "function" {
			left = "(" + left + ")"
		}
		if second.Kind == "pair" || second.Kind == "function" {
			right = "(" + right + ")"
		}
		return left + " * " + right
	}
	if first.Kind == "function" {
		left = "(" + left + ")"
	}
	return left + " -> " + right
}
func signatureType(e *Expr, variables map[string]*Type) *Type {
	if e.Kind == "type_variable" {
		if variables[e.Value] == nil {
			variables[e.Value] = fresh()
		}
		return variables[e.Value]
	}
	children := []*Type{}
	for _, child := range e.Children {
		children = append(children, signatureType(child, variables))
	}
	return constructed(e.Kind, children...)
}
func identicalTypes(a, b *Type) bool {
	a, b = resolve(a), resolve(b)
	if a.Kind == "var" || b.Kind == "var" {
		return a == b
	}
	if a.Kind != b.Kind {
		return false
	}
	for j, child := range a.Children {
		if !identicalTypes(child, b.Children[j]) {
			return false
		}
	}
	return true
}
func signatureMatches(inferred, declared *Type, assignments map[*Type]*Type) bool {
	inferred, declared = resolve(inferred), resolve(declared)
	if inferred.Kind == "var" {
		if previous, exists := assignments[inferred]; exists {
			return identicalTypes(previous, declared)
		}
		assignments[inferred] = declared
		return true
	}
	if declared.Kind == "var" || inferred.Kind != declared.Kind {
		return false
	}
	for j, child := range inferred.Children {
		if !signatureMatches(child, declared.Children[j], assignments) {
			return false
		}
	}
	return true
}
func checkSignatures(g *Group, signatures []*Item) {
	for j, binding := range g.Bindings {
		signature := signatures[j]
		if signature == nil {
			continue
		}
		declared := signatureType(signature.Declared, map[string]*Type{})
		inferred := binding.Scheme.Type
		if !signatureMatches(inferred, declared, map[*Type]*Type{}) {
			panic(&TypeError{Kind: "signature", Name: binding.Name.Spelling, Position: binding.Name.Position, Expected: inferred, Found: declared})
		}
		binding.Scheme = Scheme{declared, freeVariables(declared)}
	}
}
func editDistance(a, b string) int {
	previous := make([]int, len(b)+1)
	for j := range previous {
		previous[j] = j
	}
	for i := 0; i < len(a); i++ {
		current := make([]int, len(b)+1)
		current[0] = i + 1
		for j := 0; j < len(b); j++ {
			substitution := 0
			if a[i] != b[j] {
				substitution = 1
			}
			current[j+1] = min(current[j]+1, previous[j+1]+1, previous[j]+substitution)
		}
		previous = current
	}
	return previous[len(b)]
}
func typeErrorMessage(err *TypeError) string {
	printer := &TypePrinter{}
	switch err.Kind {
	case "unbound":
		message := "unbound variable '" + err.Name + "'"
		best, bestDistance := "", 3
		for _, candidate := range err.Candidates {
			distance := editDistance(err.Name, candidate)
			if distance <= 2 && distance < len(err.Name) && (distance < bestDistance || distance == bestDistance && (best == "" || candidate < best)) {
				best = candidate
				bestDistance = distance
			}
		}
		if best != "" {
			message += " (did you mean '" + best + "'?)"
		}
		return message
	case "not_function":
		return "expected a function but found " + printer.print(err.Found)
	case "duplicate_pattern":
		return "variable '" + err.Name + "' is bound twice in this pattern"
	case "duplicate_let":
		return "variable '" + err.Name + "' is bound twice in this let"
	case "recursive_function":
		return "'" + err.Name + "' in let rec must be a function"
	case "signature":
		return "'" + err.Name + "' has type " + printer.print(err.Expected) + " but its signature is " + printer.print(err.Found)
	case "check":
		message := "expected " + printer.print(err.Expected) + " but found " + printer.print(err.Found)
		failure := err.Failure
		if failure.Infinite {
			variable, value := failure.Expected, failure.Found
			if variable.Kind != "var" {
				variable, value = value, variable
			}
			message += " (infinite type " + printer.print(variable) + " = " + printer.print(value) + ")"
		} else if failure.Nested {
			message += " (" + printer.print(failure.Expected) + " vs " + printer.print(failure.Found) + ")"
		}
		return message
	}
	return ""
}
func builtins() (TypeEnv, ValueEnv) {
	types := TypeEnv{}
	values := ValueEnv{}
	for _, name := range []string{"fst", "snd"} {
		a, b := fresh(), fresh()
		result := a
		if name == "snd" {
			result = b
		}
		types[name] = Scheme{constructed("function", constructed("pair", a, b), result), map[*Type]bool{a: true, b: true}}
	}
	types["not"] = Scheme{Type: constructed("function", boolType, boolType)}
	types["string_of_int"] = Scheme{Type: constructed("function", intType, stringType)}
	result := fresh()
	types["failwith"] = Scheme{constructed("function", stringType, result), map[*Type]bool{result: true}}
	for name := range types {
		values[name] = &Value{Kind: "function", Builtin: name}
	}
	return types, values
}
func quoteString(value string) string {
	var b strings.Builder
	b.WriteByte('"')
	for j := 0; j < len(value); j++ {
		switch value[j] {
		case '\\':
			b.WriteString(`\\`)
		case '"':
			b.WriteString(`\"`)
		case '\n':
			b.WriteString(`\n`)
		case '\t':
			b.WriteString(`\t`)
		default:
			b.WriteByte(value[j])
		}
	}
	b.WriteByte('"')
	return b.String()
}
func printValue(v *Value) string {
	switch v.Kind {
	case "integer":
		return strconv.FormatInt(v.Integer, 10)
	case "boolean":
		if v.Boolean {
			return "true"
		}
		return "false"
	case "string":
		return quoteString(v.Text)
	case "pair":
		return "(" + printValue(v.Items[0]) + ", " + printValue(v.Items[1]) + ")"
	case "list":
		parts := []string{}
		for _, item := range v.Items {
			parts = append(parts, printValue(item))
		}
		return "[" + strings.Join(parts, "; ") + "]"
	}
	return "<fun>"
}
func declaredType(e *Expr) string {
	if e.Kind == "type_variable" {
		return e.Value
	}
	if wordIn("int bool string", e.Kind) {
		return e.Kind
	}
	first := e.Children[0]
	left := declaredType(first)
	if e.Kind == "list" {
		if first.Kind == "pair" || first.Kind == "function" {
			left = "(" + left + ")"
		}
		return left + " list"
	}
	second := e.Children[1]
	right := declaredType(second)
	if e.Kind == "pair" {
		if first.Kind == "pair" || first.Kind == "function" {
			left = "(" + left + ")"
		}
		if second.Kind == "pair" || second.Kind == "function" {
			right = "(" + right + ")"
		}
		return left + " * " + right
	}
	if first.Kind == "function" {
		left = "(" + left + ")"
	}
	return left + " -> " + right
}
func parameters(e *Expr) ([]string, *Expr) {
	names := []string{}
	for e.Kind == "fun" {
		names = append(names, e.Token.Spelling)
		e = e.Children[0]
	}
	return names, e
}
func formatGroup(g *Group) string {
	prefix := "let "
	if g.Rec != nil {
		prefix = "let rec "
	}
	parts := []string{}
	for _, binding := range g.Bindings {
		params, body := parameters(binding.Expr)
		words := append([]string{binding.Name.Spelling}, params...)
		words = append(words, "=", formatExpression(body, 0))
		parts = append(parts, strings.Join(words, " "))
	}
	return prefix + strings.Join(parts, " and ")
}
func endsWithMatch(e *Expr) bool {
	if e.Kind == "match" {
		return true
	}
	if e.Kind == "let" || e.Kind == "fun" {
		return endsWithMatch(e.Children[0])
	}
	if e.Kind == "if" {
		return endsWithMatch(e.Children[2])
	}
	return false
}
func formatPattern(p *Expr) string {
	switch p.Kind {
	case "wildcard", "name":
		return p.Value
	case "integer":
		return strconv.FormatInt(p.Integer, 10)
	case "string":
		return quoteString(p.Value)
	case "boolean":
		return p.Value
	case "list":
		parts := []string{}
		for _, child := range p.Children {
			parts = append(parts, formatPattern(child))
		}
		return "[" + strings.Join(parts, "; ") + "]"
	case "pair":
		return "(" + formatPattern(p.Children[0]) + ", " + formatPattern(p.Children[1]) + ")"
	case "cons":
		left := formatPattern(p.Children[0])
		if p.Children[0].Kind == "cons" {
			left = "(" + left + ")"
		}
		return left + " :: " + formatPattern(p.Children[1])
	}
	return ""
}
func formatExpression(e *Expr, minimum int) string {
	strength := 9
	text := ""
	c := e.Children
	switch e.Kind {
	case "integer":
		text = strconv.FormatInt(e.Integer, 10)
	case "boolean", "name":
		text = e.Value
	case "string":
		text = quoteString(e.Value)
	case "fun":
		strength = 0
		params, body := parameters(e)
		text = "fun " + strings.Join(params, " ") + " -> " + formatExpression(body, 0)
	case "apply":
		strength = 8
		text = formatExpression(c[0], 8) + " " + formatExpression(c[1], 9)
	case "binary":
		var right bool
		strength, right = operator(e.Token.Spelling)
		leftMin, rightMin := strength, strength+1
		if right {
			leftMin, rightMin = strength+1, strength
		}
		text = formatExpression(c[0], leftMin) + " " + e.Token.Spelling + " " + formatExpression(c[1], rightMin)
	case "negate":
		strength = 7
		text = "-" + formatExpression(c[0], 7)
	case "if":
		strength = 0
		text = "if " + formatExpression(c[0], 0) + " then " + formatExpression(c[1], 0) + " else " + formatExpression(c[2], 0)
	case "pair":
		text = "(" + formatExpression(c[0], 0) + ", " + formatExpression(c[1], 0) + ")"
	case "list":
		parts := []string{}
		for _, child := range c {
			parts = append(parts, formatExpression(child, 0))
		}
		text = "[" + strings.Join(parts, "; ") + "]"
	case "let":
		strength = 0
		text = formatGroup(e.Group) + " in " + formatExpression(c[0], 0)
	case "match":
		strength = 0
		parts := []string{}
		for j, arm := range e.Arms {
			body := formatExpression(arm.Body, 0)
			if j+1 < len(e.Arms) && endsWithMatch(arm.Body) {
				body = "(" + body + ")"
			}
			parts = append(parts, formatPattern(arm.Pattern)+" -> "+body)
		}
		text = "match " + formatExpression(c[0], 0) + " with " + strings.Join(parts, " | ")
	}
	if strength < minimum {
		text = "(" + text + ")"
	}
	return text
}
func formatItem(item *Item) string {
	switch item.Kind {
	case "signature":
		return "val " + item.Name.Spelling + " : " + declaredType(item.Declared) + ";;"
	case "declaration":
		return formatGroup(item.Group) + ";;"
	}
	return formatExpression(item.Expr, 0) + ";;"
}

type Cover struct {
	Tag      string
	Children []*Cover
}

func coveragePattern(p *Expr) *Cover {
	switch p.Kind {
	case "name", "wildcard":
		return nil
	case "integer":
		return &Cover{Tag: "i:" + strconv.FormatInt(p.Integer, 10)}
	case "string":
		return &Cover{Tag: "s:" + quoteString(p.Value)}
	case "boolean":
		return &Cover{Tag: "b:" + p.Value}
	case "list":
		out := &Cover{Tag: "nil"}
		for j := len(p.Children) - 1; j >= 0; j-- {
			out = &Cover{Tag: "cons", Children: []*Cover{coveragePattern(p.Children[j]), out}}
		}
		return out
	default:
		children := []*Cover{}
		for _, child := range p.Children {
			children = append(children, coveragePattern(child))
		}
		return &Cover{Tag: p.Kind, Children: children}
	}
}
func constructors(t *Type) []string {
	switch resolve(t).Kind {
	case "bool":
		return []string{"b:false", "b:true"}
	case "list":
		return []string{"nil", "cons"}
	case "pair":
		return []string{"pair"}
	}
	return nil
}
func constructorTypes(tag string, t *Type) []*Type {
	t = resolve(t)
	if tag == "pair" {
		return t.Children
	}
	if tag == "cons" {
		return []*Type{t.Children[0], t}
	}
	return nil
}
func specialize(matrix [][]*Cover, tag string, arity int) [][]*Cover {
	out := [][]*Cover{}
	for _, row := range matrix {
		head := row[0]
		if head == nil {
			out = append(out, append(make([]*Cover, arity), row[1:]...))
		} else if head.Tag == tag {
			next := append([]*Cover{}, head.Children...)
			out = append(out, append(next, row[1:]...))
		}
	}
	return out
}
func coverCode(p *Cover) string {
	if p == nil {
		return "_"
	}
	parts := ""
	for _, child := range p.Children {
		parts += coverCode(child)
	}
	return strconv.Itoa(len(p.Tag)) + ":" + p.Tag + "(" + parts + ")"
}
func coverageTypeCode(t *Type) string {
	t = resolve(t)
	if t.Kind == "var" || t.Kind == "function" {
		return "opaque"
	}
	out := t.Kind + "("
	for _, child := range t.Children {
		out += coverageTypeCode(child)
	}
	return out + ")"
}

type Coverage struct{ Memo map[string]bool }

func (c *Coverage) useful(matrix [][]*Cover, query []*Cover, types []*Type) bool {
	var key strings.Builder
	for _, row := range matrix {
		key.WriteByte('[')
		for _, p := range row {
			key.WriteString(coverCode(p))
		}
		key.WriteByte(']')
	}
	key.WriteByte('?')
	for _, p := range query {
		key.WriteString(coverCode(p))
	}
	key.WriteByte(':')
	for _, t := range types {
		key.WriteString(coverageTypeCode(t))
	}
	code := key.String()
	if value, exists := c.Memo[code]; exists {
		return value
	}
	value := c.compute(matrix, query, types)
	c.Memo[code] = value
	return value
}
func (c *Coverage) compute(matrix [][]*Cover, query []*Cover, types []*Type) bool {
	if len(query) == 0 {
		return len(matrix) == 0
	}
	if len(matrix) == 0 {
		return true
	}
	head := query[0]
	if head != nil {
		argumentTypes := constructorTypes(head.Tag, types[0])
		nextQuery := append(append([]*Cover{}, head.Children...), query[1:]...)
		nextTypes := append(append([]*Type{}, argumentTypes...), types[1:]...)
		return c.useful(specialize(matrix, head.Tag, len(head.Children)), nextQuery, nextTypes)
	}
	possible := constructors(types[0])
	present := map[string]bool{}
	for _, row := range matrix {
		if row[0] != nil {
			present[row[0].Tag] = true
		}
	}
	complete := len(possible) > 0
	for _, tag := range possible {
		if !present[tag] {
			complete = false
		}
	}
	if complete {
		for _, tag := range possible {
			arguments := constructorTypes(tag, types[0])
			next := append(make([]*Cover, len(arguments)), query[1:]...)
			nextTypes := append(append([]*Type{}, arguments...), types[1:]...)
			if c.useful(specialize(matrix, tag, len(arguments)), next, nextTypes) {
				return true
			}
		}
		return false
	}
	defaults := [][]*Cover{}
	for _, row := range matrix {
		if row[0] == nil {
			defaults = append(defaults, row[1:])
		}
	}
	return c.useful(defaults, query[1:], types[1:])
}

type Symbol struct {
	Name string
	Position
	Top, Used bool
}
type Warning struct {
	Position
	Order   int
	Message string
}
type GroupSymbols struct {
	Group   *Group
	Targets map[*Symbol]bool
}
type StaticChecks struct {
	Symbols    []*Symbol
	References map[*Expr]*Symbol
	Groups     []GroupSymbols
	Warnings   []Warning
}

func copySymbols(env map[string]*Symbol) map[string]*Symbol {
	out := map[string]*Symbol{}
	for name, symbol := range env {
		out[name] = symbol
	}
	return out
}
func (s *StaticChecks) symbol(name string, pos Position, top bool) *Symbol {
	symbol := &Symbol{Name: name, Position: pos, Top: top}
	s.Symbols = append(s.Symbols, symbol)
	return symbol
}
func (s *StaticChecks) pattern(p *Expr, env map[string]*Symbol) {
	if p.Kind == "name" {
		env[p.Value] = s.symbol(p.Value, p.Position, false)
	}
	for _, child := range p.Children {
		s.pattern(child, env)
	}
}
func (s *StaticChecks) group(g *Group, env map[string]*Symbol, top bool) map[string]*Symbol {
	inner := copySymbols(env)
	targets := map[*Symbol]bool{}
	for _, binding := range g.Bindings {
		symbol := s.symbol(binding.Name.Spelling, binding.Name.Position, top)
		inner[symbol.Name] = symbol
		targets[symbol] = true
	}
	s.Groups = append(s.Groups, GroupSymbols{g, targets})
	right := env
	if g.Rec != nil {
		right = inner
	}
	for _, binding := range g.Bindings {
		s.expression(binding.Expr, right)
	}
	return inner
}
func (s *StaticChecks) expression(e *Expr, env map[string]*Symbol) {
	switch e.Kind {
	case "name":
		symbol := env[e.Value]
		s.References[e] = symbol
		if symbol != nil {
			symbol.Used = true
		}
		return
	case "fun":
		inner := copySymbols(env)
		if e.Token.Spelling != "_" {
			inner[e.Token.Spelling] = s.symbol(e.Token.Spelling, e.Token.Position, false)
		}
		s.expression(e.Children[0], inner)
		return
	case "let":
		inner := s.group(e.Group, env, false)
		s.expression(e.Children[0], inner)
		return
	case "match":
		s.expression(e.Children[0], env)
		coverage := Coverage{map[string]bool{}}
		matrix := [][]*Cover{}
		types := []*Type{e.Children[0].Inferred}
		for j, arm := range e.Arms {
			query := []*Cover{coveragePattern(arm.Pattern)}
			if j > 0 && !coverage.useful(matrix, query, types) {
				s.Warnings = append(s.Warnings, Warning{arm.Pattern.Position, 2, "this match case is unused"})
			}
			matrix = append(matrix, query)
			inner := copySymbols(env)
			s.pattern(arm.Pattern, inner)
			s.expression(arm.Body, inner)
		}
		if coverage.useful(matrix, []*Cover{nil}, types) {
			s.Warnings = append(s.Warnings, Warning{e.Position, 1, "this match is not exhaustive"})
		}
		return
	}
	for _, child := range e.Children {
		s.expression(child, env)
	}
}
func walkExpr(e *Expr, visit func(*Expr)) {
	visit(e)
	if e.Group != nil {
		for _, binding := range e.Group.Bindings {
			walkExpr(binding.Expr, visit)
		}
	}
	for _, child := range e.Children {
		walkExpr(child, visit)
	}
	for _, arm := range e.Arms {
		walkExpr(arm.Body, visit)
	}
}
func (s *StaticChecks) classification(e *Expr, targets map[*Symbol]bool) string {
	_, body := parameters(e)
	references, allTail := 0, true
	var visit func(*Expr, bool)
	visit = func(n *Expr, tail bool) {
		c := n.Children
		switch n.Kind {
		case "name":
			if targets[s.References[n]] {
				references++
				allTail = false
			}
			return
		case "apply":
			arguments := []*Expr{}
			head := n
			for head.Kind == "apply" {
				arguments = append(arguments, head.Children[1])
				head = head.Children[0]
			}
			if head.Kind == "name" && targets[s.References[head]] {
				references++
				if !tail {
					allTail = false
				}
			} else {
				visit(head, false)
			}
			for j := len(arguments) - 1; j >= 0; j-- {
				visit(arguments[j], false)
			}
			return
		case "if":
			visit(c[0], false)
			visit(c[1], tail)
			visit(c[2], tail)
			return
		case "match":
			visit(c[0], false)
			for _, arm := range n.Arms {
				visit(arm.Body, tail)
			}
			return
		case "let":
			for _, binding := range n.Group.Bindings {
				visit(binding.Expr, false)
			}
			visit(c[0], tail)
			return
		case "binary":
			if n.Token.Spelling == "&&" || n.Token.Spelling == "||" {
				visit(c[0], false)
				visit(c[1], tail)
				return
			}
		}
		for _, child := range c {
			visit(child, false)
		}
	}
	visit(body, true)
	if references == 0 {
		return ""
	}
	if allTail {
		return "tail recursive"
	}
	return "recursive"
}
func staticWarnings(item *Item, env TypeEnv) []Warning {
	s := &StaticChecks{References: map[*Expr]*Symbol{}}
	names := map[string]*Symbol{}
	for name := range env {
		names[name] = nil
	}
	if item.Kind == "declaration" {
		s.group(item.Group, names, true)
	} else {
		s.expression(item.Expr, names)
	}
	for _, g := range s.Groups {
		if g.Group.Rec == nil {
			continue
		}
		used := false
		for _, binding := range g.Group.Bindings {
			walkExpr(binding.Expr, func(e *Expr) {
				if g.Targets[s.References[e]] {
					used = true
				}
			})
			binding.Classification = s.classification(binding.Expr, g.Targets)
		}
		if !used {
			s.Warnings = append(s.Warnings, Warning{*g.Group.Rec, 3, "unused rec flag"})
		}
	}
	for _, symbol := range s.Symbols {
		if !symbol.Top && !symbol.Used && !strings.HasPrefix(symbol.Name, "_") {
			s.Warnings = append(s.Warnings, Warning{symbol.Position, 4, "unused variable '" + symbol.Name + "'"})
		}
	}
	sort.SliceStable(s.Warnings, func(i, j int) bool {
		a, b := s.Warnings[i], s.Warnings[j]
		if a.Line != b.Line {
			return a.Line < b.Line
		}
		if a.Column != b.Column {
			return a.Column < b.Column
		}
		return a.Order < b.Order
	})
	return s.Warnings
}
func inferItem(item *Item, env TypeEnv, signatures []*Item) (inference *Inferencer, result *Type, failure *TypeError) {
	inference = &Inferencer{}
	defer func() {
		if value := recover(); value != nil {
			if err, ok := value.(*TypeError); ok {
				failure = err
			} else {
				panic(value)
			}
		}
	}()
	if item.Kind == "declaration" {
		inference.group(item.Group, env, false)
		checkSignatures(item.Group, signatures)
	} else {
		result = inference.expression(item.Expr, env)
	}
	return
}
func evaluateItem(item *Item, env ValueEnv, evaluator *Evaluator) (updated ValueEnv, values []*Value, failure *RuntimeError) {
	defer func() {
		if value := recover(); value != nil {
			if err, ok := value.(*RuntimeError); ok {
				failure = err
			} else {
				panic(value)
			}
		}
	}()
	if item.Kind == "declaration" {
		updated, values = evaluator.group(item.Group, env)
	} else {
		updated = env
		values = []*Value{evaluator.expression(item.Expr, env)}
	}
	return
}
func suffixClassification(binding *Binding) string {
	if binding.Classification == "" {
		return ""
	}
	return " (" + binding.Classification + ")"
}

type Counts struct{ Items, Bindings, Syntax, Type, Runtime, Warnings, Calls int }
type Reports struct {
	Sources map[string][]string
	Current string
	Stats   map[string]*Counts
	Lines   []string
}

func (r *Reports) report(kind string, pos Position, message string) {
	c := r.Stats[r.Current]
	switch kind {
	case "syntax error":
		c.Syntax++
	case "type error":
		c.Type++
	case "runtime error":
		c.Runtime++
	case "warning":
		c.Warnings++
	}
	r.Lines = append(r.Lines, fmt.Sprintf("%s:%d:%d: %s: %s", pos.File, pos.Line, pos.Column, kind, message))
	lines := r.Sources[pos.File]
	if pos.Line <= len(lines) {
		r.Lines = append(r.Lines, "    "+lines[pos.Line-1], strings.Repeat(" ", pos.Column+3)+"^")
	}
}
func syntaxMessage(t Token) string {
	if t.Kind == "invalid" {
		return t.Value
	}
	if t.Kind == "EOF" {
		return "unexpected end of file"
	}
	return "unexpected '" + t.Spelling + "'"
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
func writeLines(path string, lines []string) {
	value := strings.Join(lines, "\n") + "\n"
	if err := os.WriteFile("output/"+path, []byte(value), 0644); err != nil {
		panic(err)
	}
}
func main() {
	filenames := []string{"prelude.ml", "program.ml"}
	reports := &Reports{Sources: map[string][]string{}, Stats: map[string]*Counts{}}
	for _, filename := range filenames {
		reports.Sources[filename] = readLines("input/" + filename)
		reports.Stats[filename] = &Counts{}
	}
	typeEnv, valueEnv := builtins()
	types, values, formatted := []string{}, []string{}, []string{}
	for _, filename := range filenames {
		reports.Current = filename
		stats := reports.Stats[filename]
		pending := map[string]*Item{}
		types = append(types, "== "+filename+" ==")
		values = append(values, "== "+filename+" ==")
		formatted = append(formatted, "(* "+filename+" *)")
		parser := &Parser{Tokens: lex(filename, reports.Sources[filename])}
		evaluator := &Evaluator{}
		for parser.peek().Kind != "EOF" {
			stats.Items++
			item, syntax := parser.readItem()
			if syntax != nil {
				reports.report("syntax error", syntax.Token.Position, syntaxMessage(syntax.Token))
				parser.recoverItem()
				continue
			}
			formatted = append(formatted, formatItem(item))
			if item.Kind == "signature" {
				name := item.Name.Spelling
				if old := pending[name]; old != nil {
					reports.report("warning", old.Name.Position, "signature for '"+name+"' is never used")
				}
				pending[name] = item
				continue
			}
			signatures := []*Item{}
			if item.Kind == "declaration" {
				for _, binding := range item.Group.Bindings {
					name := binding.Name.Spelling
					signatures = append(signatures, pending[name])
					delete(pending, name)
				}
			}
			inference, inferred, typeFailure := inferItem(item, typeEnv, signatures)
			if typeFailure != nil {
				reports.report("type error", typeFailure.Position, typeErrorMessage(typeFailure))
				continue
			}
			warnings := staticWarnings(item, typeEnv)
			if item.Kind == "declaration" {
				for _, binding := range item.Group.Bindings {
					printer := &TypePrinter{}
					types = append(types, binding.Name.Spelling+" : "+printer.print(binding.Scheme.Type)+suffixClassification(binding))
				}
			} else {
				printer := &TypePrinter{}
				types = append(types, "- : "+printer.print(inferred))
			}
			sort.SliceStable(inference.Locals, func(i, j int) bool {
				a, b := inference.Locals[i].Name, inference.Locals[j].Name
				if a.Line != b.Line {
					return a.Line < b.Line
				}
				return a.Column < b.Column
			})
			for _, binding := range inference.Locals {
				printer := &TypePrinter{Quantified: binding.Scheme.Quantified, Local: true}
				types = append(types, fmt.Sprintf("  %s (%d:%d) : %s%s", binding.Name.Spelling, binding.Name.Line, binding.Name.Column, printer.print(binding.Scheme.Type), suffixClassification(binding)))
			}
			for _, warning := range warnings {
				reports.report("warning", warning.Position, warning.Message)
			}
			updated, evaluated, runtimeFailure := evaluateItem(item, valueEnv, evaluator)
			if runtimeFailure != nil {
				reports.report("runtime error", runtimeFailure.Position, runtimeFailure.Message)
				continue
			}
			if item.Kind == "declaration" {
				typeEnv = copyTypes(typeEnv)
				for j, binding := range item.Group.Bindings {
					name := binding.Name.Spelling
					typeEnv[name] = binding.Scheme
					values = append(values, name+" = "+printValue(evaluated[j]))
					stats.Bindings++
				}
				valueEnv = updated
			} else {
				values = append(values, "- = "+printValue(evaluated[0]))
			}
		}
		remaining := []*Item{}
		for _, signature := range pending {
			remaining = append(remaining, signature)
		}
		sort.Slice(remaining, func(i, j int) bool {
			a, b := remaining[i].Name, remaining[j].Name
			if a.Line != b.Line {
				return a.Line < b.Line
			}
			return a.Column < b.Column
		})
		for _, signature := range remaining {
			reports.report("warning", signature.Name.Position, "signature for '"+signature.Name.Spelling+"' is never used")
		}
		stats.Calls = evaluator.Calls
	}
	reports.Lines = append(reports.Lines, "== summary ==")
	for _, filename := range filenames {
		c := reports.Stats[filename]
		reports.Lines = append(reports.Lines, fmt.Sprintf("%s: items=%d bindings=%d syntax=%d type=%d runtime=%d warnings=%d calls=%d", filename, c.Items, c.Bindings, c.Syntax, c.Type, c.Runtime, c.Warnings, c.Calls))
	}
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	writeLines("types.txt", types)
	writeLines("values.txt", values)
	writeLines("errors.txt", reports.Lines)
	writeLines("formatted.ml", formatted)
}
