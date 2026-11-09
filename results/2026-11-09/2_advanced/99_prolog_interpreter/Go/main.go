package main

import (
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

type Writer struct {
	Quoted bool
	Names  map[*Term]string
	Serial int
}

func newWriter(quoted bool) *Writer { return &Writer{Quoted: quoted, Names: map[*Term]string{}} }
func operatorName(name string) bool {
	_, infix := infixOperators[name]
	_, prefix := prefixOperators[name]
	return infix || prefix
}
func (w *Writer) atomName(name string) string {
	if !w.Quoted {
		return name
	}
	plain := name == "[]" || name == "!" || name == ";"
	if len(name) > 0 {
		if lower(name[0]) {
			plain = true
			for i := 0; i < len(name); i++ {
				plain = plain && alphanumeric(name[i])
			}
		}
		allSymbols := true
		for i := 0; i < len(name); i++ {
			allSymbols = allSymbols && symbol(name[i])
		}
		plain = plain || allSymbols && name != "."
	}
	if plain {
		return name
	}
	var out strings.Builder
	out.WriteByte('\'')
	for i := 0; i < len(name); i++ {
		switch name[i] {
		case '\\':
			out.WriteString("\\\\")
		case '\'':
			out.WriteString("\\'")
		case '\n':
			out.WriteString("\\n")
		case '\t':
			out.WriteString("\\t")
		default:
			out.WriteByte(name[i])
		}
	}
	out.WriteByte('\'')
	return out.String()
}
func (w *Writer) write(t *Term, limit int, operand bool) string {
	t = dereference(t)
	switch t.Kind {
	case "variable":
		if name, exists := w.Names[t]; exists {
			return name
		}
		w.Serial++
		name := fmt.Sprintf("_G%d", w.Serial)
		w.Names[t] = name
		return name
	case "integer":
		return strconv.FormatInt(t.Integer, 10)
	case "atom":
		name := w.atomName(t.Name)
		if operand && operatorName(t.Name) {
			return "(" + name + ")"
		}
		return name
	}
	if isCompound(t, ".", 2) {
		elements, tail := listParts(t)
		parts := []string{}
		for _, element := range elements {
			parts = append(parts, w.write(element, 999, false))
		}
		value := "[" + strings.Join(parts, ",")
		if !isNil(tail) {
			value += "|" + w.write(tail, 999, false)
		}
		return value + "]"
	}
	if op, ok := infixOperators[t.Name]; ok && len(t.Arguments) == 2 {
		left := w.write(t.Arguments[0], op.Left, true)
		right := w.write(t.Arguments[1], op.Right, true)
		value := ""
		if t.Name == "," {
			value = left + "," + right
		} else if lower(t.Name[0]) {
			value = left + " " + t.Name + " " + right
		} else {
			before, after := "", ""
			if len(left) > 0 && symbol(left[len(left)-1]) {
				before = " "
			}
			if len(right) > 0 && symbol(right[0]) {
				after = " "
			}
			value = left + before + t.Name + after + right
		}
		if op.Priority > limit {
			value = "(" + value + ")"
		}
		return value
	}
	if priority, ok := prefixOperators[t.Name]; ok && len(t.Arguments) == 1 {
		arg := w.write(t.Arguments[0], priority, true)
		gap := ""
		if len(arg) > 0 && (symbol(arg[0]) || digit(arg[0]) || arg[0] == '(') {
			gap = " "
		}
		value := t.Name + gap + arg
		if priority > limit {
			value = "(" + value + ")"
		}
		return value
	}
	parts := []string{}
	for _, arg := range t.Arguments {
		parts = append(parts, w.write(arg, 999, false))
	}
	return w.atomName(t.Name) + "(" + strings.Join(parts, ",") + ")"
}
func termText(t *Term) string          { return newWriter(true).write(t, 1200, false) }
func indicatorText(p Indicator) string { return termText(indicatorTerm(p)) }
func control(p Indicator) bool {
	return p == (Indicator{",", 2}) || p == (Indicator{"!", 0}) || p == (Indicator{";", 2}) || p == (Indicator{"->", 2}) || p == (Indicator{"\\+", 1}) || p == (Indicator{"catch", 3}) || p.Name == "call" && p.Arity >= 1 && p.Arity <= 8
}
func builtin(p Indicator) bool {
	return deterministicIndicators[p] || p == (Indicator{"findall", 3}) || p == (Indicator{"throw", 1}) || p == (Indicator{"between", 3}) || p == (Indicator{"length", 2})
}
func goalConversion(t *Term) (*Term, bool) {
	t = dereference(t)
	if t.Kind == "variable" {
		return compound("call", t), true
	}
	if t.Kind == "integer" {
		return nil, false
	}
	if t.Kind == "compound" && len(t.Arguments) == 2 && (t.Name == "," || t.Name == ";" || t.Name == "->") {
		a, ok := goalConversion(t.Arguments[0])
		if !ok {
			return nil, false
		}
		b, ok := goalConversion(t.Arguments[1])
		if !ok {
			return nil, false
		}
		return compound(t.Name, a, b), true
	}
	return t, true
}

type ConsultStats struct{ Clauses, Errors, Warnings int }
type Consultant struct {
	Database   *Database
	Reports    []string
	Statistics map[string]*ConsultStats
}

func newConsultant() *Consultant {
	return &Consultant{Database: newDatabase(), Statistics: map[string]*ConsultStats{"prelude.pl": {}, "program.pl": {}}}
}
func (c *Consultant) warning(file string, line int, message string) {
	c.Reports = append(c.Reports, fmt.Sprintf("%s:%d: warning: %s", file, line, message))
	c.Statistics[file].Warnings++
}
func (c *Consultant) consult(file, source string) {
	reader := &Reader{Tokens: lex(source, 1)}
	lines := strings.Split(strings.TrimSuffix(source, "\n"), "\n")
	seen := map[Indicator]bool{}
	warned := map[Indicator]bool{}
	var last Indicator
	hasLast := false
	for reader.peek().Kind != "eof" {
		line := reader.peek().Position.Line
		term, issue := readClause(reader, false)
		if issue != nil {
			token := issue.Token
			c.Reports = append(c.Reports, fmt.Sprintf("%s:%d:%d: syntax error: %s", file, token.Position.Line, token.Position.Column, issue.Message))
			if token.Kind != "eof" {
				c.Reports = append(c.Reports, "    "+lines[token.Position.Line-1], strings.Repeat(" ", token.Position.Column+3)+"^")
			}
			c.Statistics[file].Errors++
			reader.Index = issue.Index
			for reader.peek().Kind != "end" && reader.peek().Kind != "eof" {
				reader.take()
			}
			if reader.peek().Kind == "end" {
				reader.take()
			}
			continue
		}
		head := term
		var body *Term
		if isCompound(term, ":-", 2) {
			head = term.Arguments[0]
			body = term.Arguments[1]
		}
		var error *Term
		if head.Kind == "variable" {
			error = atom("instantiation_error")
		} else if head.Kind == "integer" {
			error = errorTerm("type_error", atom("callable"), head)
		} else {
			p := indicator(head)
			if control(p) || builtin(p) {
				error = errorTerm("permission_error", atom("modify"), atom("static_procedure"), indicatorTerm(p))
			} else if body != nil {
				converted, ok := goalConversion(body)
				if !ok {
					error = errorTerm("type_error", atom("callable"), body)
				} else {
					body = converted
				}
			}
		}
		if error != nil {
			c.Reports = append(c.Reports, fmt.Sprintf("%s:%d: error: %s", file, line, termText(error)))
			c.Statistics[file].Errors++
			continue
		}
		p := indicator(head)
		predicate := c.Database.ensure(p)
		if file == "program.pl" && len(predicate.Clauses) > 0 && predicate.Clauses[0].File == "prelude.pl" {
			c.warning(file, line, "redefining prelude procedure "+indicatorText(p))
			predicate.Clauses = nil
		}
		if seen[p] && hasLast && last != p && !warned[p] {
			c.warning(file, line, "clauses of "+indicatorText(p)+" are not together")
			warned[p] = true
		}
		predicate.Clauses = append(predicate.Clauses, &Clause{Head: head, Body: body, File: file, Line: line})
		seen[p] = true
		last = p
		hasLast = true
		c.Statistics[file].Clauses++
		singles, repeated := []string{}, []string{}
		for _, name := range reader.Order {
			if !strings.HasPrefix(name, "_") && reader.Counts[name] == 1 {
				singles = append(singles, name)
			}
			if len(name) >= 2 && name[0] == '_' && reader.Counts[name] >= 2 {
				repeated = append(repeated, name)
			}
		}
		if len(singles) > 0 {
			c.warning(file, line, "singleton variables: "+strings.Join(singles, ", "))
		}
		if len(repeated) > 0 {
			c.warning(file, line, "variables starting with _ occur more than once: "+strings.Join(repeated, ", "))
		}
	}
}
func (c *Consultant) undefinedWarnings() {
	reported := map[Indicator]bool{}
	for _, predicate := range c.Database.Order {
		for _, clause := range predicate.Clauses {
			if clause.Body == nil {
				continue
			}
			var walk func(*Term)
			walk = func(t *Term) {
				t = dereference(t)
				if t.Kind == "variable" || t.Kind == "integer" {
					return
				}
				p := indicator(t)
				switch {
				case p.Arity == 2 && (p.Name == "," || p.Name == ";" || p.Name == "->"):
					walk(t.Arguments[0])
					walk(t.Arguments[1])
				case p == (Indicator{"\\+", 1}) || p == (Indicator{"call", 1}):
					walk(t.Arguments[0])
				case p == (Indicator{"findall", 3}):
					walk(t.Arguments[1])
				case p == (Indicator{"catch", 3}):
					walk(t.Arguments[0])
					walk(t.Arguments[2])
				default:
					if !control(p) && !builtin(p) && c.Database.Predicates[p] == nil && !reported[p] {
						reported[p] = true
						c.warning(clause.File, clause.Line, "undefined procedure "+indicatorText(p)+" called from "+indicatorText(predicate.Indicator))
					}
				}
			}
			walk(clause.Body)
		}
	}
}
func (c *Consultant) reportLines() []string {
	out := append([]string{}, c.Reports...)
	for _, file := range []string{"prelude.pl", "program.pl"} {
		s := c.Statistics[file]
		out = append(out, fmt.Sprintf("%s: clauses=%d errors=%d warnings=%d", file, s.Clauses, s.Errors, s.Warnings))
	}
	clauses := 0
	for _, p := range c.Database.Order {
		clauses += len(p.Clauses)
	}
	return append(out, fmt.Sprintf("database: predicates=%d clauses=%d", len(c.Database.Order), clauses))
}
func listing(database *Database) []string {
	out := []string{}
	for i, p := range database.Order {
		if i > 0 {
			out = append(out, "")
		}
		for _, clause := range p.Clauses {
			counts := map[*Term]int{}
			order := []*Term{}
			values := termVariables(clause.Head)
			if clause.Body != nil {
				values = append(values, termVariables(clause.Body)...)
			}
			for _, v := range values {
				if counts[v] == 0 {
					order = append(order, v)
				}
				counts[v]++
			}
			writer := newWriter(true)
			serial := 0
			for _, v := range order {
				if counts[v] == 1 {
					writer.Names[v] = "_"
				} else {
					name := string(byte('A' + serial%26))
					if serial >= 26 {
						name += strconv.Itoa(serial / 26)
					}
					writer.Names[v] = name
					serial++
				}
			}
			head := writer.write(clause.Head, 1200, false)
			if clause.Body == nil {
				out = append(out, head+".")
				continue
			}
			out = append(out, head+" :-")
			goals := []*Term{}
			body := clause.Body
			for isCompound(body, ",", 2) {
				goals = append(goals, body.Arguments[0])
				body = body.Arguments[1]
			}
			goals = append(goals, body)
			for j, goal := range goals {
				end := ","
				if j == len(goals)-1 {
					end = "."
				}
				out = append(out, "    "+writer.write(goal, 999, false)+end)
			}
		}
	}
	return out
}

type QueryVariable struct {
	Name string
	Term *Term
}

func answer(variables []QueryVariable) string {
	writer := newWriter(true)
	for _, v := range variables {
		value := dereference(v.Term)
		if value.Kind == "variable" {
			if _, exists := writer.Names[value]; !exists {
				writer.Names[value] = v.Name
			}
		}
	}
	last := map[*Term]string{}
	items := []string{}
	for _, v := range variables {
		value := dereference(v.Term)
		if value.Kind == "variable" {
			if previous, exists := last[value]; exists {
				items = append(items, previous+" = "+v.Name)
			}
			last[value] = v.Name
		} else {
			items = append(items, v.Name+" = "+writer.write(value, 699, true))
		}
	}
	if len(items) == 0 {
		return "true"
	}
	return strings.Join(items, ", ")
}

type GoalEntry struct {
	Goal            *Term
	Marker          string
	Height, Barrier int
	Frame, Context  *Choice
}
type GoalNode struct {
	Entry GoalEntry
	Next  *GoalNode
}

func prepend(entries []GoalEntry, tail *GoalNode) *GoalNode {
	for i := len(entries) - 1; i >= 0; i-- {
		tail = &GoalNode{Entry: entries[i], Next: tail}
	}
	return tail
}

type Choice struct {
	Kind                   string
	Mark                   int
	Resume                 *GoalNode
	Goal                   *Term
	Clauses                []*Clause
	NextClause, Barrier    int
	Context                *Choice
	High, NextValue, Base  int64
	Variable, Tail, Length *Term
	Catcher, Recovery      *Term
	Parent                 *Choice
	Template, Result       *Term
	Results                []*Term
}
type Profile struct{ Calls, Tries int }
type Ball struct{ Term *Term }
type Machine struct {
	Database                                   *Database
	Profiles                                   map[Indicator]*Profile
	Bindings                                   Bindings
	Goals                                      *GoalNode
	Choices                                    []*Choice
	Variables                                  []QueryVariable
	Limit                                      int
	Inferences, Created, Backtracks, Solutions int
	End                                        string
	Exception                                  *Term
	Answers                                    []string
	Output                                     strings.Builder
}

func (m *Machine) profile(p Indicator) *Profile {
	profile := m.Profiles[p]
	if profile == nil {
		profile = &Profile{}
		m.Profiles[p] = profile
	}
	return profile
}
func (m *Machine) push(choice *Choice) {
	choice.Mark = m.Bindings.mark()
	m.Choices = append(m.Choices, choice)
	m.Created++
}
func (m *Machine) cut(height int) { m.Choices = m.Choices[:height] }
func (m *Machine) inference(p Indicator) bool {
	if m.Inferences == 20000 {
		m.End = "limit"
		return false
	}
	m.Inferences++
	m.profile(p).Calls++
	return true
}
func goalEntry(goal *Term, barrier int, context *Choice) GoalEntry {
	return GoalEntry{Goal: goal, Barrier: barrier, Context: context}
}
func (m *Machine) tryClause(goal *Term, clause *Clause, barrier int, context *Choice, continuation *GoalNode) bool {
	m.profile(indicator(goal)).Tries++
	head, body := copyClause(clause)
	if !m.Bindings.unify(head, goal) {
		return false
	}
	m.Goals = continuation
	if body != nil {
		m.Goals = prepend([]GoalEntry{goalEntry(body, barrier, context)}, continuation)
	}
	return true
}
func (m *Machine) step(entry GoalEntry, continuation *GoalNode) (success bool, ball *Term) {
	defer func() {
		if failure := recover(); failure != nil {
			switch issue := failure.(type) {
			case Ball:
				ball = issue.Term
			case BuiltinIssue:
				ball = errorBall(issue.Term, indicator(dereference(entry.Goal)))
			default:
				panic(failure)
			}
		}
	}()
	c, k := entry.Barrier, entry.Context
	m.Goals = continuation
	if entry.Marker != "" {
		switch entry.Marker {
		case "ITE":
			m.cut(entry.Height)
			return true, nil
		case "NAF":
			m.cut(entry.Height)
			return false, nil
		case "EXIT":
			if len(m.Choices) > 0 && m.Choices[len(m.Choices)-1] == entry.Frame {
				m.Choices = m.Choices[:len(m.Choices)-1]
			}
			return true, nil
		case "COLLECT":
			entry.Frame.Results = append(entry.Frame.Results, copyTerm(entry.Frame.Template))
			return false, nil
		}
	}
	goal := dereference(entry.Goal)
	p := indicator(goal)
	args := goal.Arguments
	if control(p) {
		switch p.Name {
		case ",":
			m.Goals = prepend([]GoalEntry{goalEntry(args[0], c, k), goalEntry(args[1], c, k)}, continuation)
		case "!":
			m.cut(c)
		case ";":
			h := len(m.Choices)
			m.push(&Choice{Kind: "ALT", Resume: prepend([]GoalEntry{goalEntry(args[1], c, k)}, continuation)})
			if left := dereference(args[0]); isCompound(left, "->", 2) {
				m.Goals = prepend([]GoalEntry{goalEntry(left.Arguments[0], h+1, k), {Marker: "ITE", Height: h, Barrier: c, Context: k}, goalEntry(left.Arguments[1], c, k)}, continuation)
			} else {
				m.Goals = prepend([]GoalEntry{goalEntry(args[0], c, k)}, continuation)
			}
		case "->":
			h := len(m.Choices)
			m.Goals = prepend([]GoalEntry{goalEntry(args[0], h, k), {Marker: "ITE", Height: h, Barrier: c, Context: k}, goalEntry(args[1], c, k)}, continuation)
		case "\\+":
			h := len(m.Choices)
			m.push(&Choice{Kind: "ALT", Resume: continuation})
			m.Goals = prepend([]GoalEntry{goalEntry(compound("call", args[0]), c, k), {Marker: "NAF", Height: h, Barrier: c, Context: k}}, continuation)
		case "call":
			target := dereference(args[0])
			if target.Kind == "variable" {
				panic(Ball{errorBall(atom("instantiation_error"), p)})
			}
			if target.Kind == "integer" {
				panic(Ball{errorBall(errorTerm("type_error", atom("callable"), target), p)})
			}
			if len(args) > 1 {
				values := []*Term{}
				if target.Kind == "compound" {
					values = append(values, target.Arguments...)
				}
				values = append(values, args[1:]...)
				target = compound(target.Name, values...)
			}
			converted, ok := goalConversion(target)
			if !ok {
				panic(Ball{errorBall(errorTerm("type_error", atom("callable"), target), p)})
			}
			m.Goals = prepend([]GoalEntry{goalEntry(converted, len(m.Choices), k)}, continuation)
		case "catch":
			frame := &Choice{Kind: "CATCH", Resume: continuation, Catcher: args[1], Recovery: args[2], Parent: k}
			m.push(frame)
			m.Goals = prepend([]GoalEntry{goalEntry(compound("call", args[0]), c, frame), {Marker: "EXIT", Frame: frame, Barrier: c, Context: k}}, continuation)
		}
		return true, nil
	}
	if !m.inference(p) {
		return false, nil
	}
	switch p {
	case Indicator{"findall", 3}:
		frame := &Choice{Kind: "FINDALL", Resume: continuation, Template: args[0], Result: args[2]}
		m.push(frame)
		m.Goals = prepend([]GoalEntry{goalEntry(compound("call", args[1]), c, k), {Marker: "COLLECT", Frame: frame, Barrier: c, Context: k}}, nil)
		return true, nil
	case Indicator{"throw", 1}:
		value := dereference(args[0])
		if value.Kind == "variable" {
			panic(Ball{errorBall(atom("instantiation_error"), p)})
		}
		panic(Ball{value})
	case Indicator{"between", 3}:
		low := integerCheck(args[0])
		high := integerCheck(args[1])
		value := dereference(args[2])
		if value.Kind != "variable" && value.Kind != "integer" {
			predicateError(errorTerm("type_error", atom("integer"), value))
		}
		if value.Kind == "integer" {
			return value.Integer >= low && value.Integer <= high, nil
		}
		if low > high {
			return false, nil
		}
		if low < high {
			m.push(&Choice{Kind: "BETWEEN", Resume: continuation, High: high, NextValue: low + 1, Variable: args[2]})
		}
		return m.Bindings.unify(args[2], integer(low)), nil
	case Indicator{"length", 2}:
		length := dereference(args[1])
		if length.Kind != "variable" && length.Kind != "integer" {
			predicateError(errorTerm("type_error", atom("integer"), length))
		}
		if length.Kind == "integer" && length.Integer < 0 {
			predicateError(errorTerm("domain_error", atom("not_less_than_zero"), length))
		}
		elements, tail := listParts(args[0])
		base := int64(len(elements))
		if isNil(tail) {
			return m.Bindings.unify(args[1], integer(base)), nil
		}
		if tail.Kind != "variable" {
			predicateError(errorTerm("type_error", atom("list"), args[0]))
		}
		if length.Kind == "integer" {
			if length.Integer < base {
				return false, nil
			}
			values := []*Term{}
			for i := base; i < length.Integer; i++ {
				values = append(values, variable())
			}
			return m.Bindings.unify(tail, makeList(values, nil)), nil
		}
		m.push(&Choice{Kind: "LENGTH", Resume: continuation, Tail: tail, Length: args[1], Base: base, NextValue: base + 1})
		return m.Bindings.unify(tail, atom("[]")) && m.Bindings.unify(args[1], integer(base)), nil
	}
	if deterministicIndicators[p] {
		return deterministic(goal, &m.Bindings, &m.Output), nil
	}
	predicate := m.Database.Predicates[p]
	if predicate == nil {
		panic(Ball{errorBall(errorTerm("existence_error", atom("procedure"), indicatorTerm(p)), p)})
	}
	candidates := predicate.candidates(goal)
	if len(candidates) == 0 {
		return false, nil
	}
	height := len(m.Choices)
	if len(candidates) > 1 {
		m.push(&Choice{Kind: "CLAUSES", Resume: continuation, Goal: goal, Clauses: candidates, NextClause: 1, Barrier: height, Context: k})
	}
	return m.tryClause(goal, candidates[0], height, k, continuation), nil
}
func (m *Machine) backtrack() bool {
	increment := true
	for {
		if increment {
			m.Backtracks++
		}
		increment = true
		if len(m.Choices) == 0 {
			m.End = "exhausted"
			return false
		}
		choice := m.Choices[len(m.Choices)-1]
		m.Bindings.undo(choice.Mark)
		switch choice.Kind {
		case "ALT":
			m.Choices = m.Choices[:len(m.Choices)-1]
			m.Goals = choice.Resume
			return true
		case "CLAUSES":
			index := choice.NextClause
			if index == len(choice.Clauses)-1 {
				m.Choices = m.Choices[:len(m.Choices)-1]
			} else {
				choice.NextClause++
			}
			if m.tryClause(choice.Goal, choice.Clauses[index], choice.Barrier, choice.Context, choice.Resume) {
				return true
			}
		case "BETWEEN":
			if !m.inference(Indicator{"between", 3}) {
				return false
			}
			value := choice.NextValue
			if value == choice.High {
				m.Choices = m.Choices[:len(m.Choices)-1]
			} else {
				choice.NextValue++
			}
			if m.Bindings.unify(choice.Variable, integer(value)) {
				m.Goals = choice.Resume
				return true
			}
		case "LENGTH":
			if !m.inference(Indicator{"length", 2}) {
				return false
			}
			length := choice.NextValue
			choice.NextValue++
			values := []*Term{}
			for i := choice.Base; i < length; i++ {
				values = append(values, variable())
			}
			if m.Bindings.unify(choice.Tail, makeList(values, nil)) && m.Bindings.unify(choice.Length, integer(length)) {
				m.Goals = choice.Resume
				return true
			}
		case "CATCH":
			m.Choices = m.Choices[:len(m.Choices)-1]
			increment = false
		case "FINDALL":
			m.Choices = m.Choices[:len(m.Choices)-1]
			if m.Bindings.unify(makeList(choice.Results, nil), choice.Result) {
				m.Goals = choice.Resume
				return true
			}
		}
	}
}
func (m *Machine) exception(ball *Term, context *Choice) bool {
	ball = copyTerm(ball)
	for context != nil {
		index := len(m.Choices) - 1
		for m.Choices[index] != context {
			index--
		}
		m.Choices = m.Choices[:index]
		m.Bindings.undo(context.Mark)
		mark := m.Bindings.mark()
		if m.Bindings.unify(copyTerm(ball), context.Catcher) {
			m.Goals = prepend([]GoalEntry{goalEntry(compound("call", context.Recovery), len(m.Choices), context.Parent)}, context.Resume)
			return true
		}
		m.Bindings.undo(mark)
		context = context.Parent
	}
	m.Exception = ball
	m.End = "exception"
	return false
}
func (m *Machine) run(query *Term) {
	m.Goals = prepend([]GoalEntry{goalEntry(compound("call", query), 0, nil)}, nil)
	for m.End == "" {
		if m.Goals == nil {
			m.Solutions++
			value := answer(m.Variables)
			if m.Limit > 0 && m.Solutions == m.Limit || len(m.Choices) == 0 {
				m.Answers = append(m.Answers, value+".")
				m.End = "done"
				break
			}
			m.Answers = append(m.Answers, value+" ;")
			if !m.backtrack() {
				break
			}
			continue
		}
		entry := m.Goals.Entry
		continuation := m.Goals.Next
		success, ball := m.step(entry, continuation)
		if m.End != "" {
			break
		}
		if ball != nil {
			if !m.exception(ball, entry.Context) {
				break
			}
		} else if !success {
			if !m.backtrack() {
				break
			}
		}
	}
	switch m.End {
	case "exhausted":
		m.Answers = append(m.Answers, "false.")
	case "exception":
		m.Answers = append(m.Answers, "uncaught exception: "+termText(m.Exception))
	case "limit":
		m.Answers = append(m.Answers, "inference limit exceeded")
	}
}
func readText(path string) string {
	data, err := os.ReadFile(path)
	if err != nil {
		panic(err)
	}
	return string(data)
}
func save(name string, lines []string) {
	text := ""
	if len(lines) > 0 {
		text = strings.Join(lines, "\n") + "\n"
	}
	if err := os.WriteFile("output/"+name, []byte(text), 0644); err != nil {
		panic(err)
	}
}
func main() {
	consultant := newConsultant()
	for _, file := range []string{"prelude.pl", "program.pl"} {
		consultant.consult(file, readText("input/"+file))
	}
	consultant.undefinedWarnings()
	profiles := map[Indicator]*Profile{}
	answers, stats := []string{}, []string{}
	var writes strings.Builder
	totals := [4]int{}
	querySource := readText("input/queries.txt")
	lines := []string{}
	if querySource != "" {
		lines = strings.Split(strings.TrimSuffix(querySource, "\n"), "\n")
	}
	for i, line := range lines {
		number := i + 1
		answers = append(answers, line)
		fmt.Fprintf(&writes, "== query %d ==\n", number)
		marker := strings.Index(line, "?- ")
		bodyStart := marker + 3
		limit := 0
		if marker > 0 {
			value, err := strconv.Atoi(strings.TrimSpace(line[:marker]))
			if err != nil {
				panic(err)
			}
			limit = value
		}
		reader := &Reader{Tokens: lex(line[bodyStart:], bodyStart+1)}
		query, issue := readClause(reader, true)
		if issue != nil {
			answers = append(answers, fmt.Sprintf("syntax error at column %d: %s", issue.Token.Position.Column, issue.Message))
			stats = append(stats, fmt.Sprintf("query %d: syntax error", number))
			continue
		}
		variables := []QueryVariable{}
		for _, name := range reader.Order {
			if !strings.HasPrefix(name, "_") {
				variables = append(variables, QueryVariable{name, reader.Named[name]})
			}
		}
		machine := &Machine{Database: consultant.Database, Profiles: profiles, Variables: variables, Limit: limit}
		machine.run(query)
		answers = append(answers, machine.Answers...)
		text := machine.Output.String()
		writes.WriteString(text)
		if text != "" && !strings.HasSuffix(text, "\n") {
			writes.WriteByte('\n')
		}
		stats = append(stats, fmt.Sprintf("query %d: solutions=%d inferences=%d choicepoints=%d backtracks=%d", number, machine.Solutions, machine.Inferences, machine.Created, machine.Backtracks))
		totals[0] += machine.Solutions
		totals[1] += machine.Inferences
		totals[2] += machine.Created
		totals[3] += machine.Backtracks
	}
	stats = append(stats, fmt.Sprintf("total: solutions=%d inferences=%d choicepoints=%d backtracks=%d", totals[0], totals[1], totals[2], totals[3]), "== profile ==")
	indicators := []Indicator{}
	for p, profile := range profiles {
		if profile.Calls > 0 {
			indicators = append(indicators, p)
		}
	}
	sort.Slice(indicators, func(i, j int) bool {
		a, b := indicators[i], indicators[j]
		if profiles[a].Calls != profiles[b].Calls {
			return profiles[a].Calls > profiles[b].Calls
		}
		return indicatorText(a) < indicatorText(b)
	})
	for _, p := range indicators {
		line := fmt.Sprintf("%s calls=%d", indicatorText(p), profiles[p].Calls)
		if consultant.Database.Predicates[p] != nil {
			line += fmt.Sprintf(" tries=%d", profiles[p].Tries)
		}
		stats = append(stats, line)
	}
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	save("consult.txt", consultant.reportLines())
	save("listing.txt", listing(consultant.Database))
	save("answers.txt", answers)
	save("stats.txt", stats)
	if err := os.WriteFile("output/write_output.txt", []byte(writes.String()), 0644); err != nil {
		panic(err)
	}
}
