package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

type Rational struct { n, d int64 }

var one = Rational{1, 1}

func absolute(n int64) int64 {
	if n < 0 { return -n }
	return n
}
func rational(n, d int64) Rational {
	if d < 0 { n, d = -n, -d }
	a, b := absolute(n), d
	for b != 0 { a, b = b, a%b }
	return Rational{n/a, d/a}
}
func integer(n int64) Rational { return Rational{n, 1} }
func (a Rational) add(b Rational) Rational { return rational(a.n*b.d+b.n*a.d, a.d*b.d) }
func (a Rational) sub(b Rational) Rational { return rational(a.n*b.d-b.n*a.d, a.d*b.d) }
func (a Rational) mul(b Rational) Rational { return rational(a.n*b.n, a.d*b.d) }
func (a Rational) div(b Rational) Rational { return rational(a.n*b.d, a.d*b.n) }
func (a Rational) neg() Rational { return Rational{-a.n, a.d} }
func (a Rational) abs() Rational { return Rational{absolute(a.n), a.d} }
func (a Rational) compare(b Rational) int {
	left, right := a.n*b.d, b.n*a.d
	if left < right { return -1 }
	if left > right { return 1 }
	return 0
}
func (a Rational) power(k int) Rational {
	if k < 0 { a, k = rational(a.d, a.n), -k }
	result := one
	for range k { result = result.mul(a) }
	return result
}
func (a Rational) String() string {
	if a.d == 1 { return strconv.FormatInt(a.n, 10) }
	return fmt.Sprintf("%d/%d", a.n, a.d)
}
func (a Rational) decimal() string {
	sign, magnitude := "", absolute(a.n)
	if a.n < 0 { sign = "-" }
	return fmt.Sprintf("%s%d.%06d", sign, magnitude/a.d, magnitude%a.d*1_000_000/a.d)
}
func (a Rational) notation(unit string) string { return fmt.Sprintf("%s %s (%s)", a, unit, a.decimal()) }

type Dimension [7]int64

func (a Dimension) combine(b Dimension, sign int64) Dimension {
	for i := range a { a[i] += sign*b[i] }
	return a
}
func (a Dimension) scale(k int64) Dimension {
	for i := range a { a[i] *= k }
	return a
}
func (a Dimension) match(b Dimension) error {
	if a != b { return fmt.Errorf("DIMENSION MISMATCH %s vs %s", a, b) }
	return nil
}
func (a Dimension) String() string {
	names := [...]string{"kg", "m", "s", "A", "K", "mol", "cd"}
	var terms []string
	for i, k := range a {
		if k == 0 { continue }
		term := names[i]
		if k != 1 { term += "^"+strconv.FormatInt(k, 10) }
		terms = append(terms, term)
	}
	if len(terms) == 0 { return "1" }
	return strings.Join(terms, " ")
}

type Quantity struct { value Rational; dim Dimension }
type Kind struct { name string; dim Dimension }

var kinds = []Kind{
	{"dimensionless", Dimension{}}, {"length", Dimension{0,1,0,0,0,0,0}},
	{"mass", Dimension{1,0,0,0,0,0,0}}, {"time", Dimension{0,0,1,0,0,0,0}},
	{"current", Dimension{0,0,0,1,0,0,0}}, {"temperature", Dimension{0,0,0,0,1,0,0}},
	{"amount", Dimension{0,0,0,0,0,1,0}}, {"luminous_intensity", Dimension{0,0,0,0,0,0,1}},
	{"area", Dimension{0,2,0,0,0,0,0}}, {"volume", Dimension{0,3,0,0,0,0,0}},
	{"speed", Dimension{0,1,-1,0,0,0,0}}, {"acceleration", Dimension{0,1,-2,0,0,0,0}},
	{"density", Dimension{1,-3,0,0,0,0,0}}, {"momentum", Dimension{1,1,-1,0,0,0,0}},
	{"force", Dimension{1,1,-2,0,0,0,0}}, {"energy", Dimension{1,2,-2,0,0,0,0}},
	{"power", Dimension{1,2,-3,0,0,0,0}}, {"pressure", Dimension{1,-1,-2,0,0,0,0}},
	{"frequency", Dimension{0,0,-1,0,0,0,0}}, {"charge", Dimension{0,0,1,1,0,0,0}},
	{"voltage", Dimension{1,2,-3,-1,0,0,0}}, {"resistance", Dimension{1,2,-3,-2,0,0,0}},
	{"conductance", Dimension{-1,-2,3,2,0,0,0}}, {"capacitance", Dimension{-1,-2,4,2,0,0,0}},
	{"magnetic_flux", Dimension{1,2,-2,-1,0,0,0}}, {"flux_density", Dimension{1,0,-2,-1,0,0,0}},
	{"inductance", Dimension{1,2,-2,-2,0,0,0}}, {"illuminance", Dimension{0,-2,0,0,0,0,1}},
	{"catalytic_activity", Dimension{0,0,-1,0,0,1,0}},
}

func kindDimension(name string) (Dimension, bool) {
	for _, kind := range kinds { if kind.name == name { return kind.dim, true } }
	return Dimension{}, false
}
func kindName(dim Dimension) string {
	for _, kind := range kinds { if kind.dim == dim { return kind.name } }
	return "-"
}
func letter(c byte) bool { return c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' }
func digit(c byte) bool { return c >= '0' && c <= '9' }
func digits(text string) bool {
	if text == "" { return false }
	for i := range len(text) { if !digit(text[i]) { return false } }
	return true
}
func parseInteger(text string) int64 { value, _ := strconv.ParseInt(text, 10, 64); return value }
func number(text string) (Rational, error) {
	unsigned := strings.TrimPrefix(text, "-")
	var value Rational
	bad := fmt.Errorf("BAD NUMBER %s", text)
	if digits(unsigned) { value = integer(parseInteger(unsigned))
	} else if whole, tail, ok := strings.Cut(unsigned, "."); ok {
		if !digits(whole) || !digits(tail) { return Rational{}, bad }
		scale := int64(1)
		for range len(tail) { scale *= 10 }
		value = rational(parseInteger(whole)*scale+parseInteger(tail), scale)
	} else if n, d, ok := strings.Cut(unsigned, "/"); ok {
		if !digits(n) || !digits(d) || parseInteger(d) == 0 { return Rational{}, bad }
		value = rational(parseInteger(n), parseInteger(d))
	} else { return Rational{}, bad }
	if strings.HasPrefix(text, "-") { value = value.neg() }
	return value, nil
}
func exponent(text string) (int, error) {
	k := parseInteger(text)
	if k == 0 || k < -3 || k > 3 { return 0, fmt.Errorf("BAD EXPONENT %s", text) }
	return int(k), nil
}
func checkName(name string, variable bool) error {
	valid := len(name) >= 1 && len(name) <= 12
	for i := range len(name) { valid = valid && letter(name[i]) }
	if variable && (name == "abs" || name == "sqrt" || name == "min" || name == "max") { valid = false }
	if !valid { return fmt.Errorf("BAD NAME %s", name) }
	return nil
}
func integerSqrt(n int64) int64 {
	if n < 2 { return n }
	x, next := n, (n+1)/2
	for next < x { x = next; next = (x+n/x)/2 }
	return x
}

type TokenKind int
const (
	identifier TokenKind = 256+iota
	numeral
	unitToken
	invalid
	end
)
type Token struct { kind TokenKind; start, finish int; text string }
type Parser struct { source string; tokens []Token; position int }

func newParser(source string, quantity bool) *Parser {
	p := &Parser{source: source}
	for i := 0; i < len(source); {
		start, kind := i, invalid
		if letter(source[i]) {
			kind = identifier
			for i < len(source) && letter(source[i]) { i++ }
		} else if digit(source[i]) {
			kind = numeral
			for i < len(source) && digit(source[i]) { i++ }
			if quantity && i+1 < len(source) && source[i] == '.' && digit(source[i+1]) {
				i++
				for i < len(source) && digit(source[i]) { i++ }
			}
		} else if quantity && source[i] == '[' && strings.IndexByte(source[i+1:], ']') > 0 {
			kind = unitToken
			i += strings.IndexByte(source[i+1:], ']')+2
		} else {
			punctuation := "*/^()-"
			if quantity { punctuation = "+-*/^()," }
			if strings.ContainsRune(punctuation, rune(source[i])) { kind = TokenKind(source[i]) }
			i++
		}
		p.tokens = append(p.tokens, Token{kind, start, i, source[start:i]})
	}
	p.tokens = append(p.tokens, Token{end, len(source), len(source), ""})
	return p
}
func (p *Parser) current() Token { return p.tokens[p.position] }
func (p *Parser) syntax() error {
	at := "END"
	if p.current().kind != end { at = strconv.Itoa(p.current().start+1) }
	return fmt.Errorf("SYNTAX %s AT %s", p.source, at)
}
func (p *Parser) accept(kind TokenKind) bool {
	if p.current().kind != kind { return false }
	p.position++
	return true
}
func (p *Parser) expect(kind TokenKind) error {
	if p.accept(kind) { return nil }
	return p.syntax()
}
func (p *Parser) exponent() (string, error) {
	start := p.current().start
	p.accept('-')
	token := p.current()
	if token.kind != numeral || strings.Contains(token.text, ".") { return "", p.syntax() }
	p.position++
	return p.source[start:token.finish], nil
}

type UnitTerm struct { op byte; node *UnitExpr }
type UnitExpr struct {
	kind TokenKind
	text string
	child *UnitExpr
	terms []UnitTerm
	resolved Quantity
	power int
}

func (p *Parser) unitTerm() (*UnitExpr, error) {
	token := p.current()
	var result *UnitExpr
	if p.accept(identifier) { result = &UnitExpr{kind: identifier, text: token.text}
	} else if token.kind == numeral && token.text[0] != '0' {
		p.position++; result = &UnitExpr{kind: numeral, text: token.text}
	} else if p.accept('(') {
		inner, err := p.unitExpression()
		if err != nil { return nil, err }
		if err = p.expect(')'); err != nil { return nil, err }
		result = inner
	} else { return nil, p.syntax() }
	if p.accept('^') {
		text, err := p.exponent()
		if err != nil { return nil, err }
		result = &UnitExpr{kind: '^', text: text, child: result}
	}
	return result, nil
}
func (p *Parser) unitExpression() (*UnitExpr, error) {
	first, err := p.unitTerm()
	if err != nil { return nil, err }
	terms := []UnitTerm{{'*', first}}
	for p.current().kind == '*' || p.current().kind == '/' {
		op := byte(p.current().kind); p.position++
		term, err := p.unitTerm()
		if err != nil { return nil, err }
		terms = append(terms, UnitTerm{op, term})
	}
	return &UnitExpr{kind: '*', terms: terms}, nil
}
func (p *Parser) completeUnit() (*UnitExpr, error) {
	result, err := p.unitExpression()
	if err != nil { return nil, err }
	if p.current().kind != end { return nil, p.syntax() }
	return result, nil
}
func (u *UnitExpr) resolve(db *Database) error {
	switch u.kind {
	case identifier:
		value, ok := db.resolve(u.text)
		if !ok { return fmt.Errorf("UNKNOWN UNIT %s", u.text) }
		u.resolved = value
	case '^':
		if err := u.child.resolve(db); err != nil { return err }
		k, err := exponent(u.text)
		if err != nil { return err }
		u.power = k
	case '*':
		for _, term := range u.terms { if err := term.node.resolve(db); err != nil { return err } }
	}
	return nil
}
func (u *UnitExpr) value() Quantity {
	switch u.kind {
	case numeral: return Quantity{value: integer(parseInteger(u.text))}
	case identifier: return u.resolved
	case '^':
		q := u.child.value()
		return Quantity{q.value.power(u.power), q.dim.scale(int64(u.power))}
	default:
		result := Quantity{value: one}
		for _, term := range u.terms {
			right, sign := term.node.value(), int64(1)
			if term.op == '*' { result.value = result.value.mul(right.value)
			} else { result.value = result.value.div(right.value); sign = -1 }
			result.dim = result.dim.combine(right.dim, sign)
		}
		return result
	}
}

type NamePower struct { name string; exponent int64 }
type Reduced struct { coefficient Rational; names []NamePower }

func (u *UnitExpr) reduce() Reduced {
	switch u.kind {
	case numeral: return Reduced{coefficient: integer(parseInteger(u.text))}
	case identifier: return Reduced{one, []NamePower{{u.text, 1}}}
	case '^':
		result := u.child.reduce()
		result.coefficient = result.coefficient.power(u.power)
		for i := range result.names { result.names[i].exponent *= int64(u.power) }
		return result
	default:
		result := Reduced{coefficient: one}
		for _, term := range u.terms {
			right, sign := term.node.reduce(), int64(1)
			if term.op == '*' { result.coefficient = result.coefficient.mul(right.coefficient)
			} else { result.coefficient = result.coefficient.div(right.coefficient); sign = -1 }
			for _, power := range right.names {
				index := -1
				for i, old := range result.names { if old.name == power.name { index = i; break } }
				if index >= 0 { result.names[index].exponent += sign*power.exponent
				} else { result.names = append(result.names, NamePower{power.name, sign*power.exponent}) }
			}
		}
		return result
	}
}
func (u *UnitExpr) reducedText() string {
	result := u.reduce()
	var parts []string
	if result.coefficient != one { parts = append(parts, result.coefficient.String()) }
	for _, power := range result.names {
		if power.exponent == 0 { continue }
		text := power.name
		if power.exponent != 1 { text += "^"+strconv.FormatInt(power.exponent, 10) }
		parts = append(parts, text)
	}
	if len(parts) == 0 { return "1" }
	return strings.Join(parts, " ")
}

type ExprKind int
const (
	numberExpr ExprKind = iota
	unitExpr
	variableExpr
	powerExpr
	negativeExpr
	binaryExpr
	callExpr
)
type Expr struct { kind ExprKind; text, unit string; op byte; args []*Expr }

func (p *Parser) primary() (*Expr, error) {
	token := p.current()
	var result *Expr
	if p.accept(numeral) {
		result = &Expr{kind: numberExpr, text: token.text}
		if p.current().kind == unitToken {
			unit := p.current().text; p.position++
			result.kind, result.unit = unitExpr, unit[1:len(unit)-1]
		}
	} else if p.accept(unitToken) {
		result = &Expr{kind: unitExpr, text: "1", unit: token.text[1:len(token.text)-1]}
	} else if p.accept(identifier) {
		result = &Expr{kind: variableExpr, text: token.text}
		if p.accept('(') {
			first, err := p.expression()
			if err != nil { return nil, err }
			result.kind, result.args = callExpr, []*Expr{first}
			for p.accept(',') {
				arg, err := p.expression()
				if err != nil { return nil, err }
				result.args = append(result.args, arg)
			}
			if err := p.expect(')'); err != nil { return nil, err }
		}
	} else if p.accept('(') {
		inner, err := p.expression()
		if err != nil { return nil, err }
		if err = p.expect(')'); err != nil { return nil, err }
		result = inner
	} else { return nil, p.syntax() }
	if p.accept('^') {
		text, err := p.exponent()
		if err != nil { return nil, err }
		result = &Expr{kind: powerExpr, text: text, args: []*Expr{result}}
	}
	return result, nil
}
func (p *Parser) unary() (*Expr, error) {
	if !p.accept('-') { return p.primary() }
	inner, err := p.unary()
	if err != nil { return nil, err }
	return &Expr{kind: negativeExpr, args: []*Expr{inner}}, nil
}
func (p *Parser) product() (*Expr, error) {
	result, err := p.unary()
	if err != nil { return nil, err }
	for p.current().kind == '*' || p.current().kind == '/' {
		op := byte(p.current().kind); p.position++
		right, err := p.unary()
		if err != nil { return nil, err }
		result = &Expr{kind: binaryExpr, op: op, args: []*Expr{result, right}}
	}
	return result, nil
}
func (p *Parser) expression() (*Expr, error) {
	result, err := p.product()
	if err != nil { return nil, err }
	for p.current().kind == '+' || p.current().kind == '-' {
		op := byte(p.current().kind); p.position++
		right, err := p.product()
		if err != nil { return nil, err }
		result = &Expr{kind: binaryExpr, op: op, args: []*Expr{result, right}}
	}
	return result, nil
}
func (p *Parser) complete() (*Expr, error) {
	result, err := p.expression()
	if err != nil { return nil, err }
	if p.current().kind != end { return nil, p.syntax() }
	return result, nil
}
func (e *Expr) evaluate(db *Database) (Quantity, error) {
	switch e.kind {
	case numberExpr:
		value, err := number(e.text)
		return Quantity{value: value}, err
	case unitExpr:
		unit, err := db.unit(e.unit)
		if err != nil { return Quantity{}, err }
		value, err := number(e.text)
		if err != nil { return Quantity{}, err }
		unit.value = value.mul(unit.value)
		return unit, nil
	case variableExpr:
		value, ok := db.variables[e.text]
		if !ok { return Quantity{}, fmt.Errorf("UNKNOWN VARIABLE %s", e.text) }
		return value, nil
	case powerExpr:
		value, err := e.args[0].evaluate(db)
		if err != nil { return Quantity{}, err }
		k, err := exponent(e.text)
		if err != nil { return Quantity{}, err }
		if value.value.n == 0 && k < 0 { return Quantity{}, fmt.Errorf("DIVISION BY ZERO") }
		return Quantity{value.value.power(k), value.dim.scale(int64(k))}, nil
	case negativeExpr:
		value, err := e.args[0].evaluate(db)
		if err != nil { return Quantity{}, err }
		value.value = value.value.neg()
		return value, nil
	case binaryExpr:
		a, err := e.args[0].evaluate(db)
		if err != nil { return Quantity{}, err }
		b, err := e.args[1].evaluate(db)
		if err != nil { return Quantity{}, err }
		if e.op == '+' || e.op == '-' {
			if err := a.dim.match(b.dim); err != nil { return Quantity{}, err }
			if e.op == '+' { a.value = a.value.add(b.value) } else { a.value = a.value.sub(b.value) }
			return a, nil
		}
		if e.op == '/' && b.value.n == 0 { return Quantity{}, fmt.Errorf("DIVISION BY ZERO") }
		if e.op == '*' { return Quantity{a.value.mul(b.value), a.dim.combine(b.dim, 1)}, nil }
		return Quantity{a.value.div(b.value), a.dim.combine(b.dim, -1)}, nil
	default:
		arity := 0
		switch e.text {
		case "abs", "sqrt": arity = 1
		case "min", "max": arity = 2
		default: return Quantity{}, fmt.Errorf("UNKNOWN FUNCTION %s", e.text)
		}
		if len(e.args) != arity { return Quantity{}, fmt.Errorf("BAD ARGUMENTS %s", e.text) }
		a, err := e.args[0].evaluate(db)
		if err != nil { return Quantity{}, err }
		switch e.text {
		case "abs": a.value = a.value.abs(); return a, nil
		case "sqrt":
			if a.value.n < 0 { return Quantity{}, fmt.Errorf("NEGATIVE ROOT") }
			for _, k := range a.dim { if k%2 != 0 { return Quantity{}, fmt.Errorf("ODD DIMENSION %s", a.dim) } }
			n, d := integerSqrt(a.value.n), integerSqrt(a.value.d)
			if n*n != a.value.n || d*d != a.value.d { return Quantity{}, fmt.Errorf("NOT EXACT") }
			for i := range a.dim { a.dim[i] /= 2 }
			a.value = rational(n, d)
			return a, nil
		default:
			b, err := e.args[1].evaluate(db)
			if err != nil { return Quantity{}, err }
			if err := a.dim.match(b.dim); err != nil { return Quantity{}, err }
			comparison := a.value.compare(b.value)
			if e.text == "min" && comparison <= 0 || e.text == "max" && comparison >= 0 { return a, nil }
			return b, nil
		}
	}
}

type Definition struct { value Rational; unit string }
type Unit struct { symbol string; quantity Quantity; prefix bool; definition *Definition }
type Database struct { units []Unit; variables map[string]Quantity }

func newDatabase() *Database {
	builtins := []struct { symbol string; n, d int64; kind string; prefix bool }{
		{"m",1,1,"length",true}, {"g",1,1000,"mass",true}, {"s",1,1,"time",true},
		{"A",1,1,"current",true}, {"K",1,1,"temperature",true}, {"mol",1,1,"amount",true},
		{"cd",1,1,"luminous_intensity",true}, {"N",1,1,"force",true}, {"J",1,1,"energy",true},
		{"W",1,1,"power",true}, {"Pa",1,1,"pressure",true}, {"Hz",1,1,"frequency",true},
		{"C",1,1,"charge",true}, {"V",1,1,"voltage",true}, {"ohm",1,1,"resistance",true},
		{"S",1,1,"conductance",true}, {"F",1,1,"capacitance",true}, {"Wb",1,1,"magnetic_flux",true},
		{"T",1,1,"flux_density",true}, {"H",1,1,"inductance",true}, {"lx",1,1,"illuminance",true},
		{"kat",1,1,"catalytic_activity",true}, {"L",1,1000,"volume",true}, {"t",1000,1,"mass",false},
		{"min",60,1,"time",false}, {"h",3600,1,"time",false}, {"day",86400,1,"time",false},
		{"in",127,5000,"length",false}, {"ft",381,1250,"length",false}, {"yd",1143,1250,"length",false},
		{"mi",201168,125,"length",false}, {"nmi",1852,1,"length",false}, {"ha",10000,1,"area",false},
		{"kn",463,900,"speed",false}, {"bar",100000,1,"pressure",true}, {"atm",101325,1,"pressure",false},
		{"Torr",20265,152,"pressure",false}, {"cal",523,125,"energy",true}, {"Wh",3600,1,"energy",true},
		{"Ah",3600,1,"charge",true}, {"dC",1,1,"temperature",false}, {"dF",5,9,"temperature",false},
	}
	db := &Database{variables: make(map[string]Quantity)}
	for _, row := range builtins {
		dim, _ := kindDimension(row.kind)
		db.units = append(db.units, Unit{row.symbol, Quantity{rational(row.n, row.d), dim}, row.prefix, nil})
	}
	return db
}
func (db *Database) resolve(name string) (Quantity, bool) {
	for _, unit := range db.units { if unit.symbol == name { return unit.quantity, true } }
	prefixes := []struct { symbol string; n, d int64 }{
		{"G",1_000_000_000,1}, {"M",1_000_000,1}, {"k",1000,1}, {"h",100,1}, {"da",10,1},
		{"d",1,10}, {"c",1,100}, {"m",1,1000}, {"u",1,1_000_000}, {"n",1,1_000_000_000},
	}
	for _, prefix := range prefixes {
		if symbol, ok := strings.CutPrefix(name, prefix.symbol); ok {
			for _, unit := range db.units[:42] {
				if unit.prefix && unit.symbol == symbol {
					return Quantity{rational(prefix.n, prefix.d).mul(unit.quantity.value), unit.quantity.dim}, true
				}
			}
		}
	}
	return Quantity{}, false
}
func (db *Database) parseUnit(text string) (*UnitExpr, error) {
	expression, err := newParser(text, false).completeUnit()
	if err != nil { return nil, err }
	if err := expression.resolve(db); err != nil { return nil, err }
	return expression, nil
}
func (db *Database) unit(text string) (Quantity, error) {
	expression, err := db.parseUnit(text)
	if err != nil { return Quantity{}, err }
	return expression.value(), nil
}
func (db *Database) quantity(text string) (Quantity, error) {
	expression, err := newParser(text, true).complete()
	if err != nil { return Quantity{}, err }
	return expression.evaluate(db)
}
func (db *Database) simplified(dim Dimension) string {
	for _, unit := range db.units { if unit.quantity.value == one && unit.quantity.dim == dim { return unit.symbol } }
	return dim.String()
}
func (db *Database) selected(dim Dimension) []Unit {
	var selected []Unit
	for _, unit := range db.units { if unit.quantity.dim == dim { selected = append(selected, unit) } }
	sort.Slice(selected, func(i, j int) bool {
		a, b := selected[i], selected[j]
		comparison := a.quantity.value.compare(b.quantity.value)
		if comparison != 0 { return comparison < 0 }
		return a.symbol < b.symbol
	})
	return selected
}
func (db *Database) command(line string) ([]string, error) {
	w := strings.Split(line, " ")
	var output []string
	switch w[0] {
	case "DEFINE":
		if err := checkName(w[1], false); err != nil { return nil, err }
		value, err := number(w[3])
		if err != nil { return nil, err }
		unit, err := db.unit(w[4])
		if err != nil { return nil, err }
		_, kind := kindDimension(w[1]); _, taken := db.resolve(w[1])
		if kind || taken { return nil, fmt.Errorf("NAME TAKEN %s", w[1]) }
		if value.n <= 0 { return nil, fmt.Errorf("NOT POSITIVE %s", w[3]) }
		factor := value.mul(unit.value)
		db.units = append(db.units, Unit{w[1], Quantity{factor, unit.dim}, false, &Definition{value, w[4]}})
		output = append(output, fmt.Sprintf("DEFINE %s factor=%s dim=%s kind=%s", w[1], factor, unit.dim, kindName(unit.dim)))
	case "UNDEF":
		index := -1
		for i, unit := range db.units { if unit.symbol == w[1] { index = i; break } }
		if index < 0 { return nil, fmt.Errorf("NOT DEFINED %s", w[1]) }
		if index < 42 { return nil, fmt.Errorf("BUILTIN UNIT %s", w[1]) }
		db.units = append(db.units[:index], db.units[index+1:]...)
		output = append(output, "UNDEF "+w[1])
	case "DEFS":
		output = append(output, fmt.Sprintf("DEFS count=%d", len(db.units)-42))
		for _, unit := range db.units[42:] {
			output = append(output, fmt.Sprintf("DEF %s = %s %s factor=%s dim=%s", unit.symbol, unit.definition.value, unit.definition.unit, unit.quantity.value, unit.quantity.dim))
		}
	case "CONVERT", "INVERT":
		value, err := number(w[1])
		if err != nil { return nil, err }
		from, err := db.unit(w[2])
		if err != nil { return nil, err }
		to, err := db.unit(w[4])
		if err != nil { return nil, err }
		inverse := w[0] == "INVERT"
		if inverse {
			if from.dim == (Dimension{}) || from.dim.combine(to.dim, 1) != (Dimension{}) {
				return nil, fmt.Errorf("NOT RECIPROCAL %s vs %s", from.dim, to.dim)
			}
			if value.n == 0 { return nil, fmt.Errorf("DIVISION BY ZERO") }
		} else if err := from.dim.match(to.dim); err != nil { return nil, err }
		result := value.mul(from.value)
		if inverse { result = one.div(result) }
		result = result.div(to.value)
		output = append(output, fmt.Sprintf("%s %s %s = %s", w[0], value, w[2], result.notation(w[4])))
	case "DIM", "REDUCE", "SIMPLIFY":
		expression, err := db.parseUnit(w[1])
		if err != nil { return nil, err }
		unit := expression.value()
		switch w[0] {
		case "DIM": output = append(output, fmt.Sprintf("DIM %s = %s factor=%s kind=%s", w[1], unit.dim, unit.value, kindName(unit.dim)))
		case "REDUCE": output = append(output, fmt.Sprintf("REDUCE %s = %s", w[1], expression.reducedText()))
		default: output = append(output, fmt.Sprintf("SIMPLIFY %s = %s", w[1], unit.value.notation(db.simplified(unit.dim))))
		}
	case "ADD", "SUB", "MUL", "DIV", "COMPARE":
		a, err := number(w[1])
		if err != nil { return nil, err }
		first, err := db.unit(w[2])
		if err != nil { return nil, err }
		b, err := number(w[3])
		if err != nil { return nil, err }
		second, err := db.unit(w[4])
		if err != nil { return nil, err }
		target, destination := len(w) == 7, first
		if target { destination, err = db.unit(w[6]); if err != nil { return nil, err } }
		if w[0] == "ADD" || w[0] == "SUB" || w[0] == "COMPARE" {
			if err := first.dim.match(second.dim); err != nil { return nil, err }
			if target { if err := first.dim.match(destination.dim); err != nil { return nil, err } }
			left, right := a.mul(first.value), b.mul(second.value)
			if w[0] == "COMPARE" {
				relation := []string{"<", "=", ">"}[left.compare(right)+1]
				ratio := "undefined"
				if right.n != 0 { ratio = left.div(right).String() }
				output = append(output, fmt.Sprintf("COMPARE %s %s %s %s %s ratio=%s", a, w[2], relation, b, w[4], ratio))
			} else {
				op := "+"
				var result Rational
				if w[0] == "ADD" { result = left.add(right) } else { op, result = "-", left.sub(right) }
				unit := w[2]
				if target { unit = w[6] }
				output = append(output, fmt.Sprintf("%s %s %s %s %s %s = %s", w[0], a, w[2], op, b, w[4], result.div(destination.value).notation(unit)))
			}
		} else {
			product, sign, op := w[0] == "MUL", int64(1), "*"
			if !product { sign, op = -1, "/" }
			dim := first.dim.combine(second.dim, sign)
			if !product && b.n == 0 { return nil, fmt.Errorf("DIVISION BY ZERO") }
			if target { if err := dim.match(destination.dim); err != nil { return nil, err } }
			var raw Rational
			if product { raw = a.mul(b) } else { raw = a.div(b) }
			left, right := a.mul(first.value), b.mul(second.value)
			var coherent Rational
			if product { coherent = left.mul(right) } else { coherent = left.div(right) }
			prefix := fmt.Sprintf("%s %s %s %s %s %s = ", w[0], a, w[2], op, b, w[4])
			if target { output = append(output, prefix+coherent.div(destination.value).notation(w[6]))
			} else {
				rightUnit := w[4]
				if !product && strings.ContainsAny(rightUnit, "*/") { rightUnit = "("+rightUnit+")" }
				output = append(output, fmt.Sprintf("%s%s %s%s%s = %s", prefix, raw, w[2], op, rightUnit, coherent.notation(db.simplified(dim))))
			}
		}
	case "TEMP":
		value, err := number(w[1])
		if err != nil { return nil, err }
		for _, scale := range []string{w[2], w[4]} {
			if scale != "C" && scale != "F" && scale != "K" && scale != "R" { return nil, fmt.Errorf("UNKNOWN SCALE %s", scale) }
		}
		kelvin := value
		switch w[2] {
		case "C": kelvin = value.add(rational(5463, 20))
		case "F": kelvin = value.add(rational(45967, 100)).mul(rational(5, 9))
		case "R": kelvin = value.mul(rational(5, 9))
		}
		if kelvin.n < 0 { return nil, fmt.Errorf("BELOW ABSOLUTE ZERO") }
		result := kelvin
		switch w[4] {
		case "C": result = kelvin.sub(rational(5463, 20))
		case "F": result = kelvin.mul(rational(9, 5)).sub(rational(45967, 100))
		case "R": result = kelvin.mul(rational(9, 5))
		}
		output = append(output, fmt.Sprintf("TEMP %s %s = %s", value, w[2], result.notation(w[4])))
	case "LIST":
		dim, known := kindDimension(w[1])
		if !known {
			unit, err := db.unit(w[1])
			if err != nil { return nil, err }
			dim = unit.dim
		}
		units := db.selected(dim)
		output = append(output, fmt.Sprintf("LIST %s dim=%s kind=%s count=%d", w[1], dim, kindName(dim), len(units)))
		for _, unit := range units {
			origin, prefix := "builtin", "no"
			if unit.definition != nil { origin = "user" }
			if unit.prefix { prefix = "yes" }
			output = append(output, fmt.Sprintf("UNIT %s factor=%s origin=%s prefix=%s", unit.symbol, unit.quantity.value, origin, prefix))
		}
	case "TABLE":
		value, err := number(w[1])
		if err != nil { return nil, err }
		from, err := db.unit(w[2])
		if err != nil { return nil, err }
		units := db.selected(from.dim)
		output = append(output, fmt.Sprintf("TABLE %s %s dim=%s count=%d", value, w[2], from.dim, len(units)))
		for _, unit := range units { output = append(output, "ROW "+value.mul(from.value).div(unit.quantity.value).notation(unit.symbol)) }
	case "AUTO":
		value, err := number(w[1])
		if err != nil { return nil, err }
		unit, err := db.unit(w[2])
		if err != nil { return nil, err }
		index := -1
		for i, item := range db.units[:42] { if item.prefix && item.quantity.dim == unit.dim { index = i; break } }
		if index < 0 { return nil, fmt.Errorf("NO PREFIXABLE UNIT %s", unit.dim) }
		reference := db.units[index]
		scaled := value.mul(unit.value).div(reference.quantity.value)
		magnitude, k := scaled.abs(), 0
		if magnitude.n != 0 {
			if magnitude.compare(one) >= 0 {
				for k < 9 && magnitude.compare(integer(10).power(k+3)) >= 0 { k += 3 }
			} else {
				for k > -9 && magnitude.compare(integer(10).power(k)) < 0 { k -= 3 }
			}
		}
		prefix := []string{"n", "u", "m", "", "k", "M", "G"}[(k+9)/3]
		output = append(output, fmt.Sprintf("AUTO %s %s = %s", value, w[2], scaled.div(integer(10).power(k)).notation(prefix+reference.symbol)))
	case "SPLIT":
		value, err := number(w[1])
		if err != nil { return nil, err }
		unit, err := db.unit(w[2])
		if err != nil { return nil, err }
		parts := strings.Split(w[4], ",")
		destinations := make([]Quantity, len(parts))
		for i, part := range parts {
			destinations[i], err = db.unit(part)
			if err != nil { return nil, err }
		}
		if value.n < 0 { return nil, fmt.Errorf("NEGATIVE VALUE") }
		for _, destination := range destinations { if err := unit.dim.match(destination.dim); err != nil { return nil, err } }
		for i := 1; i < len(destinations); i++ {
			if destinations[i-1].value.compare(destinations[i].value) <= 0 { return nil, fmt.Errorf("UNIT ORDER") }
		}
		remaining := value.mul(unit.value)
		var pieces []string
		for i := 0; i < len(parts)-1; i++ {
			quotient := remaining.div(destinations[i].value)
			count := quotient.n/quotient.d
			remaining = remaining.sub(integer(count).mul(destinations[i].value))
			pieces = append(pieces, fmt.Sprintf("%d %s", count, parts[i]))
		}
		last := len(parts)-1
		pieces = append(pieces, remaining.div(destinations[last].value).notation(parts[last]))
		output = append(output, fmt.Sprintf("SPLIT %s %s = %s", value, w[2], strings.Join(pieces, " ")))
	case "LET":
		if err := checkName(w[1], true); err != nil { return nil, err }
		quantity, err := db.quantity(w[3])
		if err != nil { return nil, err }
		db.variables[w[1]] = quantity
		output = append(output, fmt.Sprintf("LET %s = %s", w[1], quantity.value.notation(db.simplified(quantity.dim))))
	case "EVAL":
		quantity, err := db.quantity(w[1])
		if err != nil { return nil, err }
		var result string
		if len(w) == 4 {
			unit, err := db.unit(w[3])
			if err != nil { return nil, err }
			if err := quantity.dim.match(unit.dim); err != nil { return nil, err }
			result = quantity.value.div(unit.value).notation(w[3])
		} else { result = quantity.value.notation(db.simplified(quantity.dim)) }
		output = append(output, fmt.Sprintf("EVAL %s = %s", w[1], result))
	case "VARS":
		output = append(output, fmt.Sprintf("VARS count=%d", len(db.variables)))
		names := make([]string, 0, len(db.variables))
		for name := range db.variables { names = append(names, name) }
		sort.Strings(names)
		for _, name := range names {
			quantity := db.variables[name]
			output = append(output, fmt.Sprintf("VAR %s = %s", name, quantity.value.notation(db.simplified(quantity.dim))))
		}
	default: return nil, fmt.Errorf("UNKNOWN COMMAND %s", w[0])
	}
	return output, nil
}

func main() {
	input := bufio.NewScanner(os.Stdin)
	input.Scan()
	count, _ := strconv.Atoi(input.Text())
	database := newDatabase()
	output := bufio.NewWriter(os.Stdout)
	defer output.Flush()
	for range count {
		input.Scan()
		lines, err := database.command(input.Text())
		if err != nil { fmt.Fprintln(output, "ERROR", err)
		} else { for _, line := range lines { fmt.Fprintln(output, line) } }
	}
}
