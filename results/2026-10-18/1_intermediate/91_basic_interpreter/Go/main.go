package main

import (
	"bufio"
	"fmt"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

type Token struct {
	Kind, Text string
	Value      any
}
type Expr struct {
	Kind, Type string
	Value      any
	Args       []*Expr
}

func node(kind, typ string, value any, args ...*Expr) *Expr {
	return &Expr{kind, typ, value, args}
}

type PrintItem struct {
	Kind string
	Expr *Expr
}
type Clause struct {
	Line    int
	HasLine bool
	Body    []*Statement
}
type Statement struct {
	Kind                 string
	Line                 int
	Next                 *Statement
	Expr, Target         *Expr
	Targets, Expressions []*Expr
	Values               []any
	Numbers              []int
	Name, Mode           string
	Clauses              []Clause
	Items                []PrintItem
}
type SyntaxFault struct{}
type BasicFault struct{ Message string }

func syntax()             { panic(SyntaxFault{}) }
func fault(reason string) { panic(BasicFault{reason}) }

var signatures = map[string][]string{
	"ABS": {"I"}, "SGN": {"I"}, "INT": {"I"}, "SQR": {"I"}, "RND": {"I"},
	"LEN": {"S"}, "ASC": {"S"}, "VAL": {"S"}, "CHR$": {"I"}, "STR$": {"I"},
	"LEFT$": {"SI"}, "RIGHT$": {"SI"}, "MID$": {"SI", "SII"}, "INSTR": {"SS"},
}
var errors = map[string]int{
	"NEXT WITHOUT FOR": 1, "RETURN WITHOUT GOSUB": 3, "OUT OF DATA": 4,
	"ILLEGAL FUNCTION CALL": 5, "OVERFLOW": 6, "OUT OF MEMORY": 7,
	"UNDEFINED LINE NUMBER": 8, "SUBSCRIPT OUT OF RANGE": 9,
	"DUPLICATE DEFINITION": 10, "DIVISION BY ZERO": 11, "TYPE MISMATCH": 13,
	"STRING TOO LONG": 15, "RESUME WITHOUT ERROR": 20,
	"FOR WITHOUT NEXT": 26, "WHILE WITHOUT WEND": 29,
	"WEND WITHOUT WHILE": 30, "INPUT PAST END": 62,
}
var operators = [][]string{
	{"OR"}, {"AND"}, {}, {"=", "<>", "<", ">", "<=", ">="},
	{"+", "-"}, {"*", "/", "MOD"}, {}, {"^"},
}

func contains(words []string, word string) bool {
	for _, w := range words {
		if w == word {
			return true
		}
	}
	return false
}
func digit(c byte) bool { return c >= '0' && c <= '9' }
func upper(c byte) bool { return c >= 'A' && c <= 'Z' }
func variable(name string) bool {
	if len(name) == 0 || !upper(name[0]) {
		return false
	}
	suffix := name
	if suffix[len(suffix)-1] == '$' {
		suffix = suffix[:len(suffix)-1]
	}
	if len(suffix) == 1 {
		return true
	}
	return len(suffix) == 2 && digit(suffix[1])
}
func nameType(name string) string {
	if strings.HasSuffix(name, "$") {
		return "S"
	}
	return "I"
}
func valueType(value any) string {
	if _, ok := value.(string); ok {
		return "S"
	}
	return "I"
}

func tokenize(text string) []Token {
	tokens := []Token{}
	for p := 0; p < len(text); {
		ch := text[p]
		if ch == ' ' {
			p++
			continue
		}
		if ch == '"' {
			end := strings.IndexByte(text[p+1:], '"')
			if end < 0 {
				syntax()
			}
			end += p + 1
			tokens = append(tokens, Token{"S", text[p : end+1], text[p+1 : end]})
			p = end + 1
		} else if digit(ch) {
			start := p
			for p < len(text) && digit(text[p]) {
				p++
			}
			word := text[start:p]
			n, e := strconv.Atoi(word)
			if e != nil || n > 32767 {
				syntax()
			}
			tokens = append(tokens, Token{"I", word, n})
		} else if upper(ch) {
			if strings.HasPrefix(text[p:], "REM") {
				tokens = append(tokens, Token{"W", "REM", "REM"})
				break
			}
			start := p
			for p < len(text) && (upper(text[p]) || digit(text[p])) {
				p++
			}
			if p < len(text) && text[p] == '$' {
				p++
			}
			word := text[start:p]
			tokens = append(tokens, Token{"W", word, word})
		} else {
			if !strings.ContainsRune("+-*/^=<>() ,;:", rune(ch)) {
				syntax()
			}
			word := string(ch)
			if p+1 < len(text) {
				pair := text[p : p+2]
				if pair == "<>" || pair == "<=" || pair == ">=" {
					word = pair
				}
			}
			tokens = append(tokens, Token{"P", word, word})
			p += len(word)
		}
	}
	return append(tokens, Token{"E", "", ""})
}

type Parser struct {
	Tokens []Token
	Pos    int
}

func (p *Parser) current() Token { return p.Tokens[p.Pos] }
func (p *Parser) at(word string) bool {
	t := p.current()
	return (t.Kind == "P" || t.Kind == "W") && t.Text == word
}
func (p *Parser) take(word string) bool {
	if !p.at(word) {
		return false
	}
	p.Pos++
	return true
}
func (p *Parser) expect(word string) {
	if !p.take(word) {
		syntax()
	}
}
func (p *Parser) number() int {
	t := p.current()
	if t.Kind != "I" {
		syntax()
	}
	p.Pos++
	return t.Value.(int)
}
func (p *Parser) integer(level int) *Expr {
	e := p.expression(level)
	if e.Type != "I" {
		syntax()
	}
	return e
}
func (p *Parser) target() *Expr {
	t := p.current()
	if t.Kind != "W" || !variable(t.Text) {
		syntax()
	}
	p.Pos++
	result := node("variable", nameType(t.Text), t.Text)
	if p.take("(") {
		result.Kind = "array"
		result.Args = append(result.Args, p.integer(0))
		if p.take(",") {
			result.Args = append(result.Args, p.integer(0))
		}
		p.expect(")")
	}
	return result
}
func (p *Parser) primary() *Expr {
	t := p.current()
	if t.Kind == "I" || t.Kind == "S" {
		p.Pos++
		return node("constant", t.Kind, t.Value)
	}
	if p.take("(") {
		e := p.expression(0)
		p.expect(")")
		return e
	}
	if t.Kind == "W" && variable(t.Text) {
		return p.target()
	}
	if p.take("ERR") {
		return node("builtin", "I", "ERR")
	}
	if p.take("ERL") {
		return node("builtin", "I", "ERL")
	}
	if t.Kind == "W" && signatures[t.Text] != nil {
		p.Pos++
		p.expect("(")
		args := []*Expr{p.expression(0)}
		for p.take(",") {
			args = append(args, p.expression(0))
		}
		p.expect(")")
		types := ""
		for _, e := range args {
			types += e.Type
		}
		if !contains(signatures[t.Text], types) {
			syntax()
		}
		return node("call", nameType(t.Text), t.Text, args...)
	}
	syntax()
	return nil
}
func (p *Parser) expression(level int) *Expr {
	if level == 2 && p.take("NOT") {
		return node("unary", "I", "NOT", p.integer(2))
	}
	if level == 6 && p.take("-") {
		return node("unary", "I", "-", p.integer(6))
	}
	if level == 8 {
		return p.primary()
	}
	left := p.expression(level + 1)
	for contains(operators[level], p.current().Text) {
		op := p.current().Text
		p.Pos++
		next := level + 1
		if level == 7 {
			next = 6
		}
		right := p.expression(next)
		if left.Type != right.Type || (left.Type == "S" && level != 3 && op != "+") {
			syntax()
		}
		typ := left.Type
		if level == 3 {
			typ = "I"
		}
		left = node("binary", typ, op, left, right)
		if level == 7 {
			break
		}
	}
	return left
}
func (p *Parser) clause() Clause {
	if p.current().Kind == "I" {
		return Clause{p.number(), true, nil}
	}
	return Clause{Body: p.list(true)}
}
func (p *Parser) list(inside bool) []*Statement {
	out := []*Statement{p.statement(inside)}
	for p.take(":") {
		out = append(out, p.statement(inside))
	}
	return out
}
func (p *Parser) statement(inside bool) *Statement {
	word := p.current().Text
	if inside && contains([]string{"IF", "FOR", "NEXT", "WHILE", "WEND", "DATA"}, word) {
		syntax()
	}
	s := &Statement{Kind: word}
	for _, kind := range []string{"REM", "RETURN", "WEND", "END", "STOP"} {
		if p.take(kind) {
			return s
		}
	}
	if p.take("PRINT") {
		lastValue := false
		for p.current().Kind != "E" && !p.at(":") && !p.at("ELSE") {
			if p.take(";") {
				s.Items = append(s.Items, PrintItem{Kind: ";"})
				lastValue = false
			} else if p.take(",") {
				s.Items = append(s.Items, PrintItem{Kind: ","})
				lastValue = false
			} else {
				kind := "value"
				if p.at("TAB") {
					kind = "TAB"
				} else if p.at("SPC") {
					kind = "SPC"
				}
				if kind == "value" && lastValue {
					syntax()
				}
				var e *Expr
				if kind == "value" {
					e = p.expression(0)
				} else {
					p.Pos++
					p.expect("(")
					e = p.integer(0)
					p.expect(")")
				}
				s.Items = append(s.Items, PrintItem{kind, e})
				lastValue = kind == "value"
			}
		}
		return s
	}
	if p.take("INPUT") || p.take("READ") || p.take("DIM") {
		for {
			t := p.target()
			if word == "DIM" && t.Kind != "array" {
				syntax()
			}
			s.Targets = append(s.Targets, t)
			if !p.take(",") {
				break
			}
		}
		return s
	}
	if p.take("DATA") {
		for {
			negative := p.take("-")
			t := p.current()
			if t.Kind != "I" && (t.Kind != "S" || negative) {
				syntax()
			}
			p.Pos++
			v := t.Value
			if negative {
				v = -v.(int)
			}
			s.Values = append(s.Values, v)
			if !p.take(",") {
				break
			}
		}
		return s
	}
	if p.take("IF") {
		s.Expr = p.integer(0)
		p.expect("THEN")
		s.Clauses = append(s.Clauses, p.clause())
		if p.take("ELSE") {
			s.Clauses = append(s.Clauses, p.clause())
		}
		if p.current().Kind != "E" {
			syntax()
		}
		return s
	}
	if p.take("GOTO") || p.take("GOSUB") {
		s.Numbers = append(s.Numbers, p.number())
		return s
	}
	if p.take("ON") {
		if p.take("ERROR") {
			s.Kind = "handler"
			p.expect("GOTO")
			s.Numbers = append(s.Numbers, p.number())
		} else {
			s.Expr = p.integer(0)
			if p.take("GOTO") {
				s.Mode = "GOTO"
			} else {
				p.expect("GOSUB")
				s.Mode = "GOSUB"
			}
			s.Numbers = append(s.Numbers, p.number())
			for p.take(",") {
				s.Numbers = append(s.Numbers, p.number())
			}
		}
		return s
	}
	if p.take("RESUME") {
		if p.take("NEXT") {
			s.Mode = "NEXT"
		} else if p.current().Kind == "I" {
			s.Mode = "line"
			s.Numbers = append(s.Numbers, p.number())
		}
		return s
	}
	if p.take("FOR") {
		t := p.current()
		if t.Kind != "W" || !variable(t.Text) || nameType(t.Text) != "I" {
			syntax()
		}
		s.Name = t.Text
		p.Pos++
		p.expect("=")
		s.Expressions = append(s.Expressions, p.integer(0))
		p.expect("TO")
		s.Expressions = append(s.Expressions, p.integer(0))
		if p.take("STEP") {
			s.Expressions = append(s.Expressions, p.integer(0))
		} else {
			s.Expressions = append(s.Expressions, node("constant", "I", 1))
		}
		return s
	}
	if p.take("NEXT") {
		t := p.current()
		if t.Kind == "W" && variable(t.Text) && nameType(t.Text) == "I" {
			s.Name = t.Text
			p.Pos++
		}
		return s
	}
	if p.take("WHILE") || p.take("RANDOMIZE") {
		s.Expr = p.integer(0)
		return s
	}
	if p.take("RESTORE") {
		if p.current().Kind == "I" {
			s.Numbers = append(s.Numbers, p.number())
		}
		return s
	}
	p.take("LET")
	s.Kind = "assign"
	s.Target = p.target()
	p.expect("=")
	s.Expr = p.expression(0)
	if s.Expr.Type != s.Target.Type {
		syntax()
	}
	return s
}
func (p *Parser) parse() []*Statement {
	result := p.list(false)
	if p.current().Kind != "E" {
		syntax()
	}
	return result
}

type ArrayDef struct {
	Bounds []int
	Values []any
}
type Address struct {
	Name    string
	Index   int
	IsArray bool
}
type Frame struct {
	Kind        string
	Position    *Statement
	Name        string
	Limit, Step int
}
type DataValue struct {
	Line  int
	Value any
}
type ProgramLine struct {
	Number int
	Body   []*Statement
}

type Machine struct {
	Inputs                                       []string
	Variables                                    map[string]any
	Arrays                                       map[string]*ArrayDef
	Stack                                        []Frame
	Entries                                      map[int]*Statement
	Sequence                                     []*Statement
	Data                                         []DataValue
	DataPos, InputPos, Random, Handler, Err, Erl int
	Handling                                     bool
	Remembered                                   *Statement
	Buffer                                       string
	Output                                       []string
}

func newMachine(inputs []string) *Machine {
	return &Machine{
		Inputs: inputs, Variables: map[string]any{}, Arrays: map[string]*ArrayDef{},
		Entries: map[int]*Statement{}, Random: 1,
	}
}
func (m *Machine) endLine() {
	m.Output = append(m.Output, strings.TrimRight(m.Buffer, " "))
	m.Buffer = ""
}
func (m *Machine) message(s string) {
	if len(m.Buffer) > 0 {
		m.endLine()
	}
	m.Output = append(m.Output, s)
}
func checked(value int) int {
	if value < -32768 || value > 32767 {
		fault("OVERFLOW")
	}
	return value
}
func (m *Machine) get(name string) any {
	if v, ok := m.Variables[name]; ok {
		return v
	}
	if nameType(name) == "S" {
		return ""
	}
	return 0
}
func (m *Machine) declare(name string, bounds []int) {
	count := 1
	for _, b := range bounds {
		count *= b + 1
	}
	initial := any(0)
	if nameType(name) == "S" {
		initial = ""
	}
	arr := &ArrayDef{Bounds: bounds, Values: make([]any, count)}
	for i := range arr.Values {
		arr.Values[i] = initial
	}
	m.Arrays[name] = arr
}
func (m *Machine) address(target *Expr) Address {
	name := target.Value.(string)
	if target.Kind == "variable" {
		return Address{Name: name}
	}
	indices := make([]int, len(target.Args))
	for i, e := range target.Args {
		indices[i] = m.evaluate(e).(int)
	}
	arr, ok := m.Arrays[name]
	if !ok {
		bounds := make([]int, len(indices))
		for i := range bounds {
			bounds[i] = 10
		}
		m.declare(name, bounds)
		arr = m.Arrays[name]
	}
	if len(indices) != len(arr.Bounds) {
		fault("SUBSCRIPT OUT OF RANGE")
	}
	index := 0
	for i, n := range indices {
		if n < 0 || n > arr.Bounds[i] {
			fault("SUBSCRIPT OUT OF RANGE")
		}
		index = index*(arr.Bounds[i]+1) + n
	}
	return Address{name, index, true}
}
func (m *Machine) load(a Address) any {
	if !a.IsArray {
		return m.get(a.Name)
	}
	return m.Arrays[a.Name].Values[a.Index]
}
func (m *Machine) store(a Address, value any) {
	if !a.IsArray {
		m.Variables[a.Name] = value
	} else {
		m.Arrays[a.Name].Values[a.Index] = value
	}
}
func (m *Machine) evaluate(e *Expr) any {
	op := e.Value
	if e.Kind == "constant" {
		return op
	}
	if e.Kind == "variable" || e.Kind == "array" {
		return m.load(m.address(e))
	}
	if e.Kind == "builtin" {
		if op == "ERR" {
			return m.Err
		}
		return m.Erl
	}
	if e.Kind == "unary" {
		a := m.evaluate(e.Args[0]).(int)
		if op == "NOT" {
			return ^a
		}
		return checked(-a)
	}
	args := make([]any, len(e.Args))
	for i, child := range e.Args {
		args[i] = m.evaluate(child)
	}
	if e.Kind == "call" {
		return m.call(op.(string), args)
	}
	a, b := args[0], args[1]
	if contains(operators[3], op.(string)) {
		cmp := 0
		if x, ok := a.(string); ok {
			cmp = strings.Compare(x, b.(string))
		} else {
			x, y := a.(int), b.(int)
			if x < y {
				cmp = -1
			} else if x > y {
				cmp = 1
			}
		}
		success := false
		switch op {
		case "=":
			success = cmp == 0
		case "<>":
			success = cmp != 0
		case "<":
			success = cmp < 0
		case ">":
			success = cmp > 0
		case "<=":
			success = cmp <= 0
		case ">=":
			success = cmp >= 0
		}
		if success {
			return -1
		}
		return 0
	}
	if e.Type == "S" {
		result := a.(string) + b.(string)
		if len(result) > 255 {
			fault("STRING TOO LONG")
		}
		return result
	}
	x, y := a.(int), b.(int)
	switch op {
	case "+":
		return checked(x + y)
	case "-":
		return checked(x - y)
	case "*":
		return checked(x * y)
	case "/":
		if y == 0 {
			fault("DIVISION BY ZERO")
		}
		return checked(x / y)
	case "MOD":
		if y == 0 {
			fault("DIVISION BY ZERO")
		}
		return x - y*(x/y)
	case "^":
		if y < 0 {
			fault("ILLEGAL FUNCTION CALL")
		}
		if (x > 1 || x < -1) && y > 15 {
			fault("OVERFLOW")
		}
		result := 1
		for range y {
			result = checked(result * x)
		}
		return result
	case "AND":
		return x & y
	case "OR":
		return x | y
	}
	fault("ILLEGAL FUNCTION CALL")
	return 0
}

var valRegex = regexp.MustCompile(`^ *([+-]?[0-9]+)`)

func (m *Machine) call(name string, args []any) any {
	a := args[0]
	var b, c any
	if len(args) > 1 {
		b = args[1]
	}
	if len(args) > 2 {
		c = args[2]
	}
	switch name {
	case "ABS":
		n := a.(int)
		if n < 0 {
			n = -n
		}
		return checked(n)
	case "SGN":
		n := a.(int)
		if n < 0 {
			return -1
		}
		if n > 0 {
			return 1
		}
		return 0
	case "INT":
		return a
	case "SQR":
		n := a.(int)
		if n < 0 {
			fault("ILLEGAL FUNCTION CALL")
		}
		result := 0
		for (result+1)*(result+1) <= n {
			result++
		}
		return result
	case "RND":
		n := a.(int)
		if n < 1 {
			fault("ILLEGAL FUNCTION CALL")
		}
		m.Random = m.Random * 48271 % 2147483647
		return m.Random%n + 1
	case "LEN":
		return len(a.(string))
	case "ASC":
		text := a.(string)
		if len(text) == 0 {
			fault("ILLEGAL FUNCTION CALL")
		}
		return int(text[0])
	case "VAL":
		match := valRegex.FindStringSubmatch(a.(string))
		if match == nil {
			return 0
		}
		n, e := strconv.Atoi(strings.TrimSpace(match[1]))
		if e != nil {
			fault("OVERFLOW")
		}
		return checked(n)
	case "CHR$":
		n := a.(int)
		if n < 32 || n > 126 {
			fault("ILLEGAL FUNCTION CALL")
		}
		return string(byte(n))
	case "STR$":
		return strconv.Itoa(a.(int))
	case "LEFT$":
		text, n := a.(string), b.(int)
		if n < 0 {
			fault("ILLEGAL FUNCTION CALL")
		}
		if n > len(text) {
			n = len(text)
		}
		return text[:n]
	case "RIGHT$":
		text, n := a.(string), b.(int)
		if n < 0 {
			fault("ILLEGAL FUNCTION CALL")
		}
		if n > len(text) {
			n = len(text)
		}
		return text[len(text)-n:]
	case "MID$":
		text, start := a.(string), b.(int)
		if start < 1 {
			fault("ILLEGAL FUNCTION CALL")
		}
		if c != nil && c.(int) < 0 {
			fault("ILLEGAL FUNCTION CALL")
		}
		start--
		if start > len(text) {
			start = len(text)
		}
		end := len(text)
		if c != nil {
			end = start + c.(int)
			if end > len(text) {
				end = len(text)
			}
		}
		return text[start:end]
	case "INSTR":
		return strings.Index(a.(string), b.(string)) + 1
	}
	fault("ILLEGAL FUNCTION CALL")
	return nil
}
func (m *Machine) line(number int) *Statement {
	s, ok := m.Entries[number]
	if !ok {
		fault("UNDEFINED LINE NUMBER")
	}
	return s
}
func (m *Machine) push(f Frame) {
	if len(m.Stack) == 100 {
		fault("OUT OF MEMORY")
	}
	m.Stack = append(m.Stack, f)
}
func (m *Machine) search(kind, name string) int {
	for i := len(m.Stack) - 1; i >= 0; i-- {
		f := m.Stack[i]
		if f.Kind == "GOSUB" {
			break
		}
		if f.Kind == kind && (name == "" || f.Name == name) {
			return i
		}
	}
	return -1
}
func (m *Machine) matching(s *Statement, opening, closing string) *Statement {
	start := -1
	for i, t := range m.Sequence {
		if t == s {
			start = i
			break
		}
	}
	depth := 0
	for i := start + 1; i < len(m.Sequence); i++ {
		t := m.Sequence[i]
		if t.Kind == opening {
			depth++
		} else if t.Kind == closing {
			if depth == 0 {
				return t.Next
			}
			depth--
		}
	}
	fault(opening + " WITHOUT " + closing)
	return nil
}
func (m *Machine) subroutine(number int, after *Statement) *Statement {
	target := m.line(number)
	m.push(Frame{Kind: "GOSUB", Position: after})
	return target
}
func (m *Machine) execute(s *Statement) *Statement {
	next := s.Next
	switch s.Kind {
	case "assign":
		a := m.address(s.Target)
		m.store(a, m.evaluate(s.Expr))
	case "PRINT":
		for _, item := range s.Items {
			if item.Kind == "," {
				m.Buffer += strings.Repeat(" ", 10-len(m.Buffer)%10)
			} else if item.Kind != ";" {
				value := m.evaluate(item.Expr)
				if item.Kind == "value" {
					m.Buffer += fmt.Sprint(value)
				} else {
					n := value.(int)
					if n < 0 {
						fault("ILLEGAL FUNCTION CALL")
					}
					if item.Kind == "TAB" && n > len(m.Buffer) {
						n -= len(m.Buffer)
					} else if item.Kind == "TAB" {
						n = 0
					}
					m.Buffer += strings.Repeat(" ", n)
				}
			}
		}
		if len(s.Items) == 0 || s.Items[len(s.Items)-1].Kind != ";" &&
			s.Items[len(s.Items)-1].Kind != "," {
			m.endLine()
		}
	case "INPUT", "READ":
		for _, target := range s.Targets {
			a := m.address(target)
			var value any
			if s.Kind == "READ" {
				if m.DataPos >= len(m.Data) {
					fault("OUT OF DATA")
				}
				value = m.Data[m.DataPos].Value
				m.DataPos++
				if valueType(value) != target.Type {
					fault("TYPE MISMATCH")
				}
			} else {
				for {
					if m.InputPos >= len(m.Inputs) {
						fault("INPUT PAST END")
					}
					text := m.Inputs[m.InputPos]
					m.InputPos++
					if target.Type == "S" {
						value = text
						break
					}
					n, e := strconv.Atoi(text)
					if e == nil && n >= -32768 && n <= 32767 &&
						regexp.MustCompile(`^-?[0-9]+$`).MatchString(text) {
						value = n
						break
					}
					m.message("?REDO FROM START")
				}
			}
			m.store(a, value)
		}
	case "RESTORE":
		if len(s.Numbers) == 0 {
			m.DataPos = 0
		} else {
			number := s.Numbers[0]
			m.line(number)
			m.DataPos = len(m.Data)
			for i, d := range m.Data {
				if d.Line >= number {
					m.DataPos = i
					break
				}
			}
		}
	case "IF":
		ix := 0
		if m.evaluate(s.Expr).(int) == 0 {
			ix = 1
		}
		if ix < len(s.Clauses) {
			clause := s.Clauses[ix]
			if clause.HasLine {
				next = m.line(clause.Line)
			} else {
				next = clause.Body[0]
			}
		}
	case "GOTO":
		next = m.line(s.Numbers[0])
	case "GOSUB":
		next = m.subroutine(s.Numbers[0], next)
	case "ON":
		n := m.evaluate(s.Expr).(int)
		if n < 0 {
			fault("ILLEGAL FUNCTION CALL")
		}
		if n >= 1 && n <= len(s.Numbers) {
			if s.Mode == "GOTO" {
				next = m.line(s.Numbers[n-1])
			} else {
				next = m.subroutine(s.Numbers[n-1], next)
			}
		}
	case "RETURN":
		index := -1
		for i := len(m.Stack) - 1; i >= 0; i-- {
			if m.Stack[i].Kind == "GOSUB" {
				index = i
				break
			}
		}
		if index < 0 {
			fault("RETURN WITHOUT GOSUB")
		}
		next = m.Stack[index].Position
		m.Stack = m.Stack[:index]
	case "FOR":
		from, limit, step := m.evaluate(s.Expressions[0]).(int),
			m.evaluate(s.Expressions[1]).(int),
			m.evaluate(s.Expressions[2]).(int)
		if step == 0 {
			fault("ILLEGAL FUNCTION CALL")
		}
		index := m.search("FOR", s.Name)
		if index >= 0 {
			m.Stack = m.Stack[:index]
		}
		m.Variables[s.Name] = from
		if (step > 0 && from > limit) || (step < 0 && from < limit) {
			next = m.matching(s, "FOR", "NEXT")
		} else {
			m.push(Frame{"FOR", next, s.Name, limit, step})
		}
	case "NEXT":
		index := m.search("FOR", s.Name)
		if index < 0 {
			fault("NEXT WITHOUT FOR")
		}
		m.Stack = m.Stack[:index+1]
		f := m.Stack[index]
		value := checked(m.get(f.Name).(int) + f.Step)
		m.Variables[f.Name] = value
		if (f.Step > 0 && value > f.Limit) || (f.Step < 0 && value < f.Limit) {
			m.Stack = m.Stack[:index]
		} else {
			next = f.Position
		}
	case "WHILE":
		if m.evaluate(s.Expr).(int) == 0 {
			next = m.matching(s, "WHILE", "WEND")
		} else {
			m.push(Frame{Kind: "WHILE", Position: s})
		}
	case "WEND":
		index := m.search("WHILE", "")
		if index < 0 {
			fault("WEND WITHOUT WHILE")
		}
		next = m.Stack[index].Position
		m.Stack = m.Stack[:index]
	case "DIM":
		for _, t := range s.Targets {
			name := t.Value.(string)
			bounds := make([]int, len(t.Args))
			for i, e := range t.Args {
				bounds[i] = m.evaluate(e).(int)
			}
			if _, ok := m.Arrays[name]; ok {
				fault("DUPLICATE DEFINITION")
			}
			size := 1
			for _, bound := range bounds {
				if bound < 0 {
					fault("ILLEGAL FUNCTION CALL")
				}
				size *= bound + 1
			}
			if size > 10000 {
				fault("OUT OF MEMORY")
			}
			m.declare(name, bounds)
		}
	case "RANDOMIZE":
		seed := m.evaluate(s.Expr).(int)
		if seed < 1 {
			fault("ILLEGAL FUNCTION CALL")
		}
		m.Random = seed
	case "handler":
		if s.Numbers[0] != 0 {
			m.line(s.Numbers[0])
		}
		m.Handler = s.Numbers[0]
	case "RESUME":
		if !m.Handling {
			fault("RESUME WITHOUT ERROR")
		}
		if s.Mode == "line" {
			next = m.line(s.Numbers[0])
		} else if s.Mode == "NEXT" {
			next = m.Remembered.Next
		} else {
			next = m.Remembered
		}
		m.Handling = false
	case "STOP":
		m.message("BREAK IN LINE " + strconv.Itoa(s.Line))
		return nil
	case "END":
		return nil
	}
	return next
}
func (m *Machine) connect(body []*Statement, after *Statement, number int) {
	next := after
	for i := len(body) - 1; i >= 0; i-- {
		s := body[i]
		s.Line = number
		s.Next = next
		for _, clause := range s.Clauses {
			m.connect(clause.Body, next, number)
		}
		next = s
	}
}
func (m *Machine) finish() []string {
	if len(m.Buffer) > 0 {
		m.endLine()
	}
	m.Output = append(m.Output, "READY")
	return m.Output
}
func safeParse(text string) (result []*Statement, err bool) {
	defer func() {
		if e := recover(); e != nil {
			if _, ok := e.(SyntaxFault); !ok {
				panic(e)
			}
			err = true
		}
	}()
	result = (&Parser{Tokens: tokenize(text)}).parse()
	return
}
func (m *Machine) safeExecute(s *Statement) (next *Statement, reason string) {
	defer func() {
		if e := recover(); e != nil {
			if fault, ok := e.(BasicFault); ok {
				reason = fault.Message
			} else {
				panic(e)
			}
		}
	}()
	next = m.execute(s)
	return
}
func (m *Machine) run(source map[int]string) []string {
	numbers := make([]int, 0, len(source))
	for n := range source {
		numbers = append(numbers, n)
	}
	sort.Ints(numbers)
	parsed := []ProgramLine{}
	for _, n := range numbers {
		body, err := safeParse(source[n])
		if err {
			m.message(fmt.Sprintf("ERROR IN LINE %d: SYNTAX ERROR", n))
			return m.finish()
		}
		parsed = append(parsed, ProgramLine{n, body})
	}
	var after *Statement
	for i := len(parsed) - 1; i >= 0; i-- {
		entry := parsed[i]
		m.connect(entry.Body, after, entry.Number)
		m.Entries[entry.Number] = entry.Body[0]
		after = entry.Body[0]
	}
	for _, entry := range parsed {
		for _, s := range entry.Body {
			m.Sequence = append(m.Sequence, s)
			if s.Kind == "DATA" {
				for _, value := range s.Values {
					m.Data = append(m.Data, DataValue{s.Line, value})
				}
			}
		}
	}
	for position := after; position != nil; {
		current := position
		next, reason := m.safeExecute(current)
		if reason != "" {
			if m.Handler != 0 && !m.Handling {
				m.Err = errors[reason]
				m.Erl = current.Line
				m.Remembered = current
				m.Handling = true
				target := m.Entries[m.Handler]
				if target == nil {
					m.message(fmt.Sprintf("ERROR IN LINE %d: UNDEFINED LINE NUMBER", current.Line))
					position = nil
				} else {
					position = target
				}
			} else {
				m.message(fmt.Sprintf("ERROR IN LINE %d: %s", current.Line, reason))
				position = nil
			}
		} else {
			position = next
		}
	}
	return m.finish()
}
func main() {
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 4096), 8*1024*1024)
	scanner.Scan()
	count, _ := strconv.Atoi(strings.TrimSuffix(scanner.Text(), "\r"))
	out := bufio.NewWriter(os.Stdout)
	defer out.Flush()
	for range count {
		source := map[int]string{}
		for scanner.Scan() {
			text := strings.TrimSuffix(scanner.Text(), "\r")
			if text == "RUN" {
				break
			}
			index := strings.IndexByte(text, ' ')
			key := text
			if index >= 0 {
				key = text[:index]
			}
			n, _ := strconv.Atoi(key)
			if index < 0 {
				delete(source, n)
			} else {
				source[n] = strings.TrimLeft(text[index+1:], " ")
			}
		}
		inputs := []string{}
		for scanner.Scan() {
			text := strings.TrimSuffix(scanner.Text(), "\r")
			if text == "END" {
				break
			}
			inputs = append(inputs, text)
		}
		for _, line := range newMachine(inputs).run(source) {
			fmt.Fprintln(out, line)
		}
	}
}
