package main

import (
	"bufio"
	"cmp"
	"errors"
	"fmt"
	"os"
	"slices"
	"strconv"
	"strings"
)

func failure(message string) error { return errors.New("ERROR " + message) }
func abs(n int64) int64 { if n < 0 { return -n }; return n }
func gcd(a, b int64) int64 {
	a, b = abs(a), abs(b)
	for b != 0 { a, b = b, a%b }
	return a
}
func integer(text string) int { n, _ := strconv.Atoi(text); return n }

type fraction struct { n, d int64 }
var zero = fraction{0, 1}
var one = fraction{1, 1}
func rational(n, d int64) fraction {
	if d < 0 { n, d = -n, -d }
	g := gcd(n, d)
	return fraction{n/g, d/g}
}
func whole(n int) fraction { return fraction{int64(n), 1} }
func parseFraction(text string) (fraction, error) {
	a, b, found := strings.Cut(text, "/")
	n, _ := strconv.ParseInt(a, 10, 64)
	d := int64(1)
	if found { d, _ = strconv.ParseInt(b, 10, 64) }
	if d == 0 { return zero, failure("ZERO DENOMINATOR") }
	return rational(n, d), nil
}
func (a fraction) add(b fraction) fraction { return rational(a.n*b.d+b.n*a.d, a.d*b.d) }
func (a fraction) sub(b fraction) fraction { return rational(a.n*b.d-b.n*a.d, a.d*b.d) }
func (a fraction) mul(b fraction) fraction { return rational(a.n*b.n, a.d*b.d) }
func (a fraction) div(b fraction) fraction { return rational(a.n*b.d, a.d*b.n) }
func (a fraction) neg() fraction { return fraction{-a.n, a.d} }
func (a fraction) abs() fraction { return fraction{abs(a.n), a.d} }
func (a fraction) sign() int { return cmp.Compare(a.n, 0) }
func (a fraction) compare(b fraction) int { return cmp.Compare(a.n*b.d, b.n*a.d) }
func (a fraction) power(n int) fraction {
	result := one
	for range n { result = result.mul(a) }
	return result
}
func (a fraction) String() string {
	if a.d == 1 { return strconv.FormatInt(a.n, 10) }
	return fmt.Sprintf("%d/%d", a.n, a.d)
}

type polynomial []fraction
func coefficients(n int) polynomial {
	p := make(polynomial, n)
	for i := range p { p[i] = zero }
	return p
}
func normalize(p polynomial) polynomial {
	for len(p) > 0 && p[len(p)-1].n == 0 { p = p[:len(p)-1] }
	return p
}
func constant(value fraction) polynomial { return normalize(polynomial{value}) }
func linear(value, slope fraction) polynomial { return normalize(polynomial{value, slope}) }
func (a polynomial) degree() int { return len(a)-1 }
func (a polynomial) leading() fraction { return a[len(a)-1] }
func (a polynomial) at(i int) fraction { if i < len(a) { return a[i] }; return zero }
func (a polynomial) add(b polynomial) polynomial {
	p := coefficients(max(len(a), len(b)))
	for i := range p { p[i] = a.at(i).add(b.at(i)) }
	return normalize(p)
}
func (a polynomial) sub(b polynomial) polynomial {
	p := coefficients(max(len(a), len(b)))
	for i := range p { p[i] = a.at(i).sub(b.at(i)) }
	return normalize(p)
}
func (a polynomial) neg() polynomial {
	p := coefficients(len(a))
	for i, c := range a { p[i] = c.neg() }
	return p
}
func (a polynomial) scale(factor fraction) polynomial {
	p := coefficients(len(a))
	for i, c := range a { p[i] = c.mul(factor) }
	return normalize(p)
}
func (a polynomial) divideScalar(divisor fraction) polynomial {
	p := coefficients(len(a))
	for i, c := range a { p[i] = c.div(divisor) }
	return normalize(p)
}
func (a polynomial) mul(b polynomial) polynomial {
	if len(a) == 0 || len(b) == 0 { return nil }
	p := coefficients(len(a)+len(b)-1)
	for i, x := range a {
		for j, y := range b { p[i+j] = p[i+j].add(x.mul(y)) }
	}
	return normalize(p)
}
func (a polynomial) power(n int) polynomial {
	if n != 0 && len(a) == 0 { return nil }
	if len(a) == 1 && a[0].d == 1 && abs(a[0].n) == 1 {
		if a[0].n < 0 && n%2 == 1 { return constant(whole(-1)) }
		return constant(one)
	}
	p := constant(one)
	for range n { p = p.mul(a) }
	return p
}
func (a polynomial) divide(b polynomial) (polynomial, polynomial) {
	q := coefficients(max(0, len(a)-len(b)+1))
	r := slices.Clone(a)
	for len(r) != 0 && len(r) >= len(b) {
		factor, shift := r.leading().div(b.leading()), len(r)-len(b)
		q[shift] = factor
		for j, c := range b { r[shift+j] = r[shift+j].sub(factor.mul(c)) }
		r = normalize(r)
	}
	return normalize(q), r
}
func (a polynomial) quotient(b polynomial) polynomial { q, _ := a.divide(b); return q }
func (a polynomial) remainder(b polynomial) polynomial { _, r := a.divide(b); return r }
func (a polynomial) monic() polynomial {
	if len(a) == 0 { return nil }
	return a.divideScalar(a.leading())
}
func (a polynomial) derivative() polynomial {
	p := coefficients(max(0, len(a)-1))
	for i := 1; i < len(a); i++ { p[i-1] = whole(i).mul(a[i]) }
	return p
}
func (a polynomial) differentiate(n int) polynomial {
	for i := 0; i < n && len(a) != 0; i++ { a = a.derivative() }
	return a
}
func (a polynomial) integral() polynomial {
	p := coefficients(len(a)+1)
	for i, c := range a { p[i+1] = c.div(whole(i+1)) }
	return normalize(p)
}
func (a polynomial) evaluate(x fraction) fraction {
	result := zero
	for i := len(a)-1; i >= 0; i-- { result = result.mul(x).add(a[i]) }
	return result
}
func (a polynomial) compose(b polynomial) polynomial {
	var p polynomial
	for i := len(a)-1; i >= 0; i-- { p = p.mul(b).add(constant(a[i])) }
	return p
}
func (a polynomial) gcd(b polynomial) polynomial {
	for len(b) != 0 { a, b = b, a.remainder(b) }
	return a.monic()
}
type bezout struct { g, s, t polynomial }
func (a polynomial) extendedGCD(b polynomial) bezout {
	r0, r1 := a, b
	s0, s1, t0, t1 := constant(one), polynomial(nil), polynomial(nil), constant(one)
	for len(r1) != 0 {
		q, r := r0.divide(r1)
		s, t := s0.sub(q.mul(s1)), t0.sub(q.mul(t1))
		r0, r1 = r1, r
		s0, s1 = s1, s
		t0, t1 = t1, t
	}
	if len(r0) == 0 { return bezout{r0, s0, t0} }
	return bezout{r0.monic(), s0.divideScalar(r0.leading()), t0.divideScalar(r0.leading())}
}
func (a polynomial) content() fraction {
	denominator, numerator := int64(1), int64(0)
	for _, c := range a {
		denominator = denominator*c.d/gcd(denominator, c.d)
		numerator = gcd(numerator, c.n)
	}
	if a.leading().n < 0 { numerator = -numerator }
	return rational(numerator, denominator)
}
func (a polynomial) primitive() polynomial { return a.divideScalar(a.content()) }
func (a polynomial) squareFree() polynomial {
	if a.degree() < 1 { return a }
	return a.quotient(a.gcd(a.derivative()))
}
func (a polynomial) isOne() bool { return len(a) == 1 && a[0] == one }
func (a polynomial) checkProduct(b polynomial) error {
	if len(a) != 0 && len(b) != 0 && a.degree()+b.degree() > 30 { return failure("DEGREE LIMIT") }
	return nil
}
func (a polynomial) checkPower(n int) error {
	if len(a) != 0 && a.degree()*n > 30 { return failure("DEGREE LIMIT") }
	return nil
}
func (a polynomial) checkComposition(b polynomial) error {
	if a.degree() >= 1 && b.degree() >= 1 && a.degree()*b.degree() > 30 { return failure("DEGREE LIMIT") }
	return nil
}
func (a polynomial) nonzero() error { if len(a) == 0 { return failure("ZERO POLYNOMIAL") }; return nil }
func (a polynomial) divisor() error { if len(a) == 0 { return failure("DIVISION BY ZERO") }; return nil }
func (a polynomial) positiveDegree() error { if a.degree() == 0 { return failure("DEGREE TOO LOW") }; return nil }
func (a polynomial) format(variable string) string {
	var text strings.Builder
	for i := len(a)-1; i >= 0; i-- {
		c := a[i]
		if c.n == 0 { continue }
		if text.Len() == 0 { if c.n < 0 { text.WriteByte('-') } } else if c.n < 0 { text.WriteString(" - ") } else { text.WriteString(" + ") }
		if i == 0 || c.abs() != one { text.WriteString(c.abs().String()) }
		if i > 0 { text.WriteString(variable) }
		if i > 1 { fmt.Fprintf(&text, "^%d", i) }
	}
	if text.Len() == 0 { return "0" }
	return text.String()
}

type expressionKind uint8
const (
	literalExpression expressionKind = iota
	variableExpression
	referenceExpression
	negativeExpression
	binaryExpression
	powerExpression
	callExpression
)
type expression struct {
	kind expressionKind
	number int
	name string
	operation byte
	left, right *expression
}
func (e *expression) evaluate(names map[string]polynomial) (polynomial, error) {
	switch e.kind {
	case literalExpression: return constant(whole(e.number)), nil
	case variableExpression: return linear(zero, one), nil
	case referenceExpression:
		p, found := names[e.name]
		if !found { return nil, fmt.Errorf("ERROR UNKNOWN %s", e.name) }
		return p.differentiate(e.number), nil
	}
	a, err := e.left.evaluate(names)
	if err != nil { return nil, err }
	if e.kind == negativeExpression { return a.neg(), nil }
	if e.kind == powerExpression {
		if err := a.checkPower(e.number); err != nil { return nil, err }
		return a.power(e.number), nil
	}
	b, err := e.right.evaluate(names)
	if err != nil { return nil, err }
	if e.kind == callExpression {
		if err := a.checkComposition(b); err != nil { return nil, err }
		return a.compose(b), nil
	}
	switch e.operation {
	case '+': return a.add(b), nil
	case '-': return a.sub(b), nil
	case '*':
		if err := a.checkProduct(b); err != nil { return nil, err }
		return a.mul(b), nil
	default:
		if err := b.divisor(); err != nil { return nil, err }
		if b.degree() >= 1 { return nil, failure("NONCONSTANT DIVISOR") }
		return a.divideScalar(b[0]), nil
	}
}

type tokenKind uint8
const (numberToken tokenKind = iota; nameToken; symbolToken; endToken)
type token struct { kind tokenKind; text string; position int }
type parser struct { tokens []token; position int; err error }
func digit(c byte) bool { return c >= '0' && c <= '9' }
func upper(c byte) bool { return c >= 'A' && c <= 'Z' }
func newParser(source string) *parser {
	p := &parser{}
	for i := 0; i < len(source); {
		if source[i] == ' ' { i++; continue }
		start, kind := i, symbolToken
		i++
		if digit(source[start]) {
			kind = numberToken
			for i < len(source) && digit(source[i]) { i++ }
		} else if upper(source[start]) {
			kind = nameToken
			for i < len(source) && (upper(source[i]) || digit(source[i])) { i++ }
		}
		p.tokens = append(p.tokens, token{kind, source[start:i], start+1})
	}
	p.tokens = append(p.tokens, token{kind: endToken, position: len(source)+1})
	return p
}
func (p *parser) current() token { return p.tokens[p.position] }
func (p *parser) accept(symbol string) bool {
	if p.current().kind == symbolToken && p.current().text == symbol { p.position++; return true }
	return false
}
func (p *parser) syntax() *expression {
	if p.err == nil {
		if p.current().kind == endToken { p.err = failure("SYNTAX AT END") } else { p.err = fmt.Errorf("ERROR SYNTAX AT %d", p.current().position) }
	}
	return nil
}
func (p *parser) expect(symbol string) bool {
	if p.err != nil { return false }
	if !p.accept(symbol) { p.syntax(); return false }
	return true
}
func (p *parser) parse() (*expression, error) {
	result := p.expression()
	if p.err == nil && p.current().kind != endToken { p.syntax() }
	return result, p.err
}
func (p *parser) expression() *expression {
	negative := p.accept("-")
	result := p.term()
	if p.err != nil { return nil }
	if negative { result = &expression{kind: negativeExpression, left: result} }
	for {
		var operation byte
		if p.accept("+") { operation = '+' } else if p.accept("-") { operation = '-' } else { break }
		right := p.term()
		if p.err != nil { return nil }
		result = &expression{kind: binaryExpression, operation: operation, left: result, right: right}
	}
	return result
}
func (p *parser) term() *expression {
	result := p.factor()
	if p.err != nil { return nil }
	for {
		var operation byte
		if p.accept("*") { operation = '*' } else if p.accept("/") { operation = '/' } else {
			current := p.current()
			if current.kind != nameToken && !(current.kind == symbolToken && (current.text == "x" || current.text == "(")) { break }
			operation = '*'
		}
		right := p.factor()
		if p.err != nil { return nil }
		result = &expression{kind: binaryExpression, operation: operation, left: result, right: right}
	}
	return result
}
func (p *parser) factor() *expression {
	result := p.primary()
	if p.err != nil { return nil }
	if p.accept("^") {
		if p.current().kind != numberToken { return p.syntax() }
		n := integer(p.current().text)
		p.position++
		result = &expression{kind: powerExpression, number: n, left: result}
	}
	return result
}
func (p *parser) primary() *expression {
	current := p.current()
	if current.kind == numberToken { p.position++; return &expression{kind: literalExpression, number: integer(current.text)} }
	if p.accept("x") { return &expression{kind: variableExpression} }
	if current.kind == nameToken {
		p.position++
		order := 0
		for p.accept("'") { order++ }
		reference := &expression{kind: referenceExpression, name: current.text, number: order}
		if !p.accept("(") { return reference }
		argument := p.expression()
		if !p.expect(")") { return nil }
		return &expression{kind: callExpression, left: reference, right: argument}
	}
	if p.accept("(") {
		result := p.expression()
		if !p.expect(")") { return nil }
		return result
	}
	return p.syntax()
}

type root struct { value fraction; multiplicity int }
type rootResult struct { content fraction; remaining polynomial; roots []root }
func rationalRoots(a polynomial) rootResult {
	content := a.content()
	p := a.divideScalar(content)
	zeros := 0
	for p[0].n == 0 { p = p[1:]; zeros++ }
	divisors := func(n int64) []int64 {
		var result []int64
		for i := int64(1); i <= n; i++ { if n%i == 0 { result = append(result, i) } }
		return result
	}
	numerators, denominators := divisors(abs(p[0].n)), divisors(p.leading().n)
	var candidates []fraction
	for _, s := range numerators {
		for _, t := range denominators {
			if gcd(s, t) == 1 { candidates = append(candidates, fraction{-s, t}, fraction{s, t}) }
		}
	}
	slices.SortFunc(candidates, fraction.compare)
	var roots []root
	for _, r := range candidates {
		multiplicity := 0
		for p.degree() >= 1 && p.evaluate(r).n == 0 {
			p = p.quotient(linear(fraction{-r.n, 1}, fraction{r.d, 1}))
			multiplicity++
		}
		if multiplicity != 0 { roots = append(roots, root{r, multiplicity}) }
	}
	if zeros != 0 { roots = append(roots, root{zero, zeros}) }
	slices.SortFunc(roots, func(a, b root) int { return a.value.compare(b.value) })
	return rootResult{content, p, roots}
}
type factor struct { value polynomial; multiplicity int }
func squareFreeFactors(a polynomial) []factor {
	if a.degree() < 1 { return nil }
	w0 := a.monic()
	c := w0.gcd(w0.derivative())
	w := w0.quotient(c)
	var factors []factor
	for i := 1; w.degree() >= 1; i++ {
		y := w.gcd(c)
		f := w.quotient(y)
		if f.degree() >= 1 { factors = append(factors, factor{f.primitive(), i}) }
		c, w = c.quotient(y), y
	}
	return factors
}
func writeFactor(text *strings.Builder, p polynomial, multiplicity int, simpleX bool) {
	text.WriteString(" * ")
	if simpleX { text.WriteByte('x') } else { fmt.Fprintf(text, "(%s)", p.format("x")) }
	if multiplicity > 1 { fmt.Fprintf(text, "^%d", multiplicity) }
}

type bound struct { infinity int; value fraction }
func finite(value fraction) bound { return bound{0, value} }
func parseBound(text string) (bound, error) {
	if text == "-inf" { return bound{infinity: -1}, nil }
	if text == "inf" { return bound{infinity: 1}, nil }
	value, err := parseFraction(text)
	return finite(value), err
}
func (a bound) compare(b bound) int {
	if a.infinity != 0 || b.infinity != 0 { return cmp.Compare(a.infinity, b.infinity) }
	return a.value.compare(b.value)
}
func (a bound) String() string {
	if a.infinity < 0 { return "-inf" }
	if a.infinity > 0 { return "inf" }
	return a.value.String()
}
func sturmSequence(a polynomial) []polynomial {
	p := a.squareFree()
	q := p.derivative()
	sequence := []polynomial{p}
	for len(q) != 0 {
		sequence = append(sequence, q)
		p, q = q, p.remainder(q).neg()
	}
	return sequence
}
func variations(sequence []polynomial, point bound) int {
	previous, changes := 0, 0
	for _, p := range sequence {
		var sign int
		if point.infinity == 0 { sign = p.evaluate(point.value).sign() } else { sign = p.leading().sign() }
		if point.infinity < 0 && p.degree()%2 == 1 { sign = -sign }
		if sign == 0 { continue }
		if previous != 0 && previous != sign { changes++ }
		previous = sign
	}
	return changes
}
func rootCount(sequence []polynomial, low, high bound) int {
	left, right := variations(sequence, low), variations(sequence, high)
	return left-right
}
type interval struct { low, high fraction }
func examine(sequence []polynomial, low, high, width fraction, result *[]interval) {
	count := rootCount(sequence, finite(low), finite(high))
	if count >= 2 {
		middle := low.add(high).div(whole(2))
		examine(sequence, low, middle, width, result)
		examine(sequence, middle, high, width, result)
	} else if count == 1 {
		for high.sub(low).compare(width) > 0 {
			middle := low.add(high).div(whole(2))
			if rootCount(sequence, finite(low), finite(middle)) >= 1 { high = middle } else { low = middle }
		}
		*result = append(*result, interval{low, high})
	}
}
func isolate(a polynomial, precision int) []interval {
	sequence := sturmSequence(a)
	first := sequence[0]
	maximum := zero
	for _, c := range first[:len(first)-1] {
		candidate := c.div(first.leading()).abs()
		if candidate.compare(maximum) > 0 { maximum = candidate }
	}
	beta, width := one.add(maximum), rational(1, int64(1)<<precision)
	var result []interval
	examine(sequence, beta.neg(), beta, width, &result)
	return result
}
func resultant(p, q polynomial) fraction {
	r := one
	for q.degree() >= 1 {
		t := p.remainder(q)
		if len(t) == 0 { return zero }
		r = r.mul(q.leading().power(p.degree()-t.degree()))
		if p.degree()*q.degree()%2 == 1 { r = r.neg() }
		p, q = q, t
	}
	return r.mul(q[0].power(p.degree()))
}
func descartes(a polynomial, negative bool) int {
	previous, count := 0, 0
	for i := len(a)-1; i >= 0; i-- {
		sign := a[i].sign()
		if negative && i%2 == 1 { sign = -sign }
		if sign == 0 { continue }
		if previous != 0 && previous != sign { count++ }
		previous = sign
	}
	return count
}
func interpolate(values []fraction) (polynomial, error) {
	m := len(values)/2
	x, d := make([]fraction, m), make([]fraction, m)
	for i := range m { x[i], d[i] = values[2*i], values[2*i+1] }
	for j := 1; j < m; j++ {
		for i := range j { if x[j] == x[i] { return nil, fmt.Errorf("ERROR DUPLICATE X %s", x[j]) } }
	}
	for j := 1; j < m; j++ {
		for i := m-1; i >= j; i-- { d[i] = d[i].sub(d[i-1]).div(x[i].sub(x[i-j])) }
	}
	var result polynomial
	for i := m-1; i >= 0; i-- { result = result.mul(linear(x[i].neg(), one)).add(constant(d[i])) }
	return result, nil
}
func special(kind string, n int) (polynomial, error) {
	if !slices.Contains([]string{"chebyshev", "chebyshev2", "legendre", "hermite", "laguerre"}, kind) { return nil, fmt.Errorf("ERROR UNKNOWN KIND %s", kind) }
	if n > 30 { return nil, failure("DEGREE LIMIT") }
	a, b := constant(one), linear(zero, one)
	if kind == "chebyshev2" || kind == "hermite" { b = linear(zero, whole(2)) }
	if kind == "laguerre" { b = linear(one, whole(-1)) }
	if n == 0 { return a, nil }
	for j := 1; j < n; j++ {
		factor, multiplier := linear(zero, whole(2)), 1
		switch kind {
		case "legendre": factor, multiplier = linear(zero, whole(2*j+1)), j
		case "hermite": multiplier = 2*j
		case "laguerre": factor, multiplier = linear(whole(2*j+1), whole(-1)), j
		}
		next := factor.mul(b).sub(a.scale(whole(multiplier)))
		if kind == "legendre" || kind == "laguerre" { next = next.scale(rational(1, int64(j+1))) }
		a, b = b, next
	}
	return b, nil
}

type named struct { name string; value polynomial }
type calculator struct { names map[string]polynomial }
func sourcePositions(command string) []int {
	switch command {
	case "ADD", "SUB", "MUL", "GCD", "LCM", "INVMOD", "COMPOSE": return []int{2, 3}
	case "POW", "DERIV", "INTEG", "TANGENT": return []int{2}
	case "MODPOW": return []int{2, 4}
	case "DIV": return []int{3, 4}
	case "XGCD": return []int{4, 5}
	case "CRT": return []int{2, 3, 4, 5}
	case "RESULTANT": return []int{1, 2}
	case "LIST", "INTERP", "SPECIAL": return nil
	default: return []int{1}
	}
}
func (c *calculator) process(line string) ([]string, error) {
	var output []string
	var pending []named
	deletion := ""
	save := func(name string, value polynomial) {
		pending = append(pending, named{name, value})
		output = append(output, name+" = "+value.format("x"))
	}
	if strings.HasPrefix(line, "DEF ") {
		parts := strings.SplitN(line, " ", 3)
		tree, err := newParser(parts[2]).parse()
		if err != nil { return nil, err }
		value, err := tree.evaluate(c.names)
		if err != nil { return nil, err }
		save(parts[1], value)
	} else {
		w := strings.Fields(line)
		command := w[0]
		if command == "DIV" && w[1] == w[2] || command == "XGCD" && (w[1] == w[2] || w[1] == w[3] || w[2] == w[3]) { return nil, failure("SAME NAME") }
		var sources []polynomial
		for _, position := range sourcePositions(command) {
			p, found := c.names[w[position]]
			if !found { return nil, fmt.Errorf("ERROR UNKNOWN %s", w[position]) }
			sources = append(sources, p)
		}
		start := len(w)
		switch command { case "AREA", "TAYLOR", "EVAL", "INTERP": start = 2; case "TANGENT": start = 3 }
		var values []fraction
		for _, text := range w[start:] {
			value, err := parseFraction(text)
			if err != nil { return nil, err }
			values = append(values, value)
		}
		var bounds [2]bound
		if command == "STURM" {
			for i := range 2 {
				value, err := parseBound(w[2+i])
				if err != nil { return nil, err }
				bounds[i] = value
			}
		}
		var a, b polynomial
		if len(sources) > 0 { a = sources[0] }
		if len(sources) > 1 { b = sources[1] }
		switch command {
		case "PRINT": output = append(output, w[1]+" = "+a.format("x"))
		case "DELETE": deletion = w[1]; output = append(output, "deleted "+w[1])
		case "LIST":
			var names []string
			for name := range c.names { names = append(names, name) }
			slices.Sort(names)
			for _, name := range names { output = append(output, name+" = "+c.names[name].format("x")) }
			if len(names) == 0 { output = append(output, "no polynomials") }
		case "DEGREE":
			degree := "-inf"
			if len(a) != 0 { degree = strconv.Itoa(a.degree()) }
			output = append(output, fmt.Sprintf("deg(%s) = %s", w[1], degree))
		case "ADD": save(w[1], a.add(b))
		case "SUB": save(w[1], a.sub(b))
		case "MUL":
			if err := a.checkProduct(b); err != nil { return nil, err }
			save(w[1], a.mul(b))
		case "POW":
			n := integer(w[3])
			if err := a.checkPower(n); err != nil { return nil, err }
			save(w[1], a.power(n))
		case "DIV":
			if err := b.divisor(); err != nil { return nil, err }
			quotient, remainder := a.divide(b)
			save(w[1], quotient); save(w[2], remainder)
		case "GCD": save(w[1], a.gcd(b))
		case "XGCD":
			e := a.extendedGCD(b)
			save(w[1], e.g); save(w[2], e.s); save(w[3], e.t)
		case "LCM":
			var value polynomial
			if len(a) != 0 && len(b) != 0 {
				g := a.gcd(b)
				if a.degree()+b.degree()-g.degree() > 30 { return nil, failure("DEGREE LIMIT") }
				value = a.quotient(g).mul(b).monic()
			}
			save(w[1], value)
		case "INVMOD":
			if err := b.divisor(); err != nil { return nil, err }
			if err := b.positiveDegree(); err != nil { return nil, err }
			e := a.extendedGCD(b)
			if !e.g.isOne() { return nil, failure("NOT COPRIME") }
			save(w[1], e.s.remainder(b))
		case "CRT":
			a2, m2 := sources[2], sources[3]
			if err := b.divisor(); err != nil { return nil, err }
			if err := m2.divisor(); err != nil { return nil, err }
			if b.degree()+m2.degree() > 30 { return nil, failure("DEGREE LIMIT") }
			e := b.extendedGCD(m2)
			if !e.g.isOne() { return nil, failure("NOT COPRIME") }
			r1, r2 := a.remainder(b), a2.remainder(m2)
			u := r2.sub(r1).mul(e.s).remainder(m2)
			save(w[1], r1.add(b.mul(u)))
		case "MODPOW":
			if err := b.divisor(); err != nil { return nil, err }
			if 2*b.degree()-2 > 30 { return nil, failure("DEGREE LIMIT") }
			x, y := constant(one).remainder(b), a.remainder(b)
			for exponent := integer(w[3]); exponent != 0; {
				if exponent%2 == 1 { x = x.mul(y).remainder(b) }
				exponent /= 2
				if exponent != 0 { y = y.mul(y).remainder(b) }
			}
			save(w[1], x)
		case "DERIV": save(w[1], a.differentiate(integer(w[3])))
		case "INTEG":
			if len(a) != 0 && a.degree()+1 > 30 { return nil, failure("DEGREE LIMIT") }
			save(w[1], a.integral())
		case "AREA":
			integral := a.integral()
			high, low := integral.evaluate(values[1]), integral.evaluate(values[0])
			output = append(output, fmt.Sprintf("integral(%s, %s, %s) = %s", w[1], values[0], values[1], high.sub(low)))
		case "TANGENT":
			point := values[0]
			y, slope := a.evaluate(point), a.derivative().evaluate(point)
			save(w[1], linear(y.sub(slope.mul(point)), slope))
		case "TAYLOR":
			point := values[0]
			shifted := a.compose(linear(point, one))
			variable := "x"
			if point.n > 0 { variable = fmt.Sprintf("(x - %s)", point) }
			if point.n < 0 { variable = fmt.Sprintf("(x + %s)", point.neg()) }
			output = append(output, fmt.Sprintf("taylor(%s, %s) = %s", w[1], point, shifted.format(variable)))
		case "COMPOSE":
			if err := a.checkComposition(b); err != nil { return nil, err }
			save(w[1], a.compose(b))
		case "EVAL":
			for _, value := range values { output = append(output, fmt.Sprintf("%s(%s) = %s", w[1], value, a.evaluate(value))) }
		case "ROOTS", "FACTOR":
			if err := a.nonzero(); err != nil { return nil, err }
			roots := rationalRoots(a)
			if command == "ROOTS" {
				var entries []string
				for _, root := range roots.roots { entries = append(entries, fmt.Sprintf("%s (%d)", root.value, root.multiplicity)) }
				text := "none"
				if len(entries) != 0 { text = strings.Join(entries, ", ") }
				output = append(output, fmt.Sprintf("roots(%s) = %s", w[1], text))
			} else {
				var text strings.Builder
				fmt.Fprintf(&text, "factor(%s) = %s", w[1], roots.content)
				for _, root := range roots.roots {
					r := root.value
					writeFactor(&text, linear(fraction{-r.n, 1}, fraction{r.d, 1}), root.multiplicity, r.n == 0)
				}
				if roots.remaining.degree() >= 1 { writeFactor(&text, roots.remaining, 1, false) }
				output = append(output, text.String())
			}
		case "SQFREE":
			if err := a.nonzero(); err != nil { return nil, err }
			var text strings.Builder
			fmt.Fprintf(&text, "sqfree(%s) = %s", w[1], a.content())
			for _, factor := range squareFreeFactors(a) {
				p := factor.value
				writeFactor(&text, p, factor.multiplicity, len(p) == 2 && p[0] == zero && p[1] == one)
			}
			output = append(output, text.String())
		case "DESCARTES":
			if err := a.nonzero(); err != nil { return nil, err }
			output = append(output, fmt.Sprintf("descartes(%s) = positive %d, negative %d", w[1], descartes(a, false), descartes(a, true)))
		case "STURM":
			if err := a.nonzero(); err != nil { return nil, err }
			if bounds[0].compare(bounds[1]) >= 0 { return nil, failure("BAD INTERVAL") }
			sequence := sturmSequence(a)
			output = append(output, fmt.Sprintf("sturm(%s, %s, %s) = %d", w[1], bounds[0], bounds[1], rootCount(sequence, bounds[0], bounds[1])))
		case "ISOLATE":
			if err := a.nonzero(); err != nil { return nil, err }
			n := integer(w[2])
			var entries []string
			for _, interval := range isolate(a, n) { entries = append(entries, fmt.Sprintf("(%s, %s]", interval.low, interval.high)) }
			text := "none"
			if len(entries) != 0 { text = strings.Join(entries, ", ") }
			output = append(output, fmt.Sprintf("isolate(%s, %d) = %s", w[1], n, text))
		case "RESULTANT":
			if err := a.nonzero(); err != nil { return nil, err }
			if err := b.nonzero(); err != nil { return nil, err }
			output = append(output, fmt.Sprintf("res(%s, %s) = %s", w[1], w[2], resultant(a, b)))
		case "DISCRIM", "POWERSUM":
			if err := a.nonzero(); err != nil { return nil, err }
			if err := a.positiveDegree(); err != nil { return nil, err }
			degree := a.degree()
			if command == "DISCRIM" {
				d := resultant(a, a.derivative()).div(a.leading())
				if degree*(degree-1)/2%2 == 1 { d = d.neg() }
				output = append(output, fmt.Sprintf("disc(%s) = %s", w[1], d))
			} else {
				n, monic := integer(w[2]), a.monic()
				sums := coefficients(n+1)
				var entries []string
				for j := 1; j <= n; j++ {
					value := zero
					if j <= degree { value = whole(j).mul(monic[degree-j]) }
					for i := 1; i <= min(j-1, degree); i++ { value = value.add(monic[degree-i].mul(sums[j-i])) }
					sums[j] = value.neg()
					entries = append(entries, sums[j].String())
				}
				output = append(output, fmt.Sprintf("powersum(%s) = %s", w[1], strings.Join(entries, ", ")))
			}
		case "INTERP":
			value, err := interpolate(values)
			if err != nil { return nil, err }
			save(w[1], value)
		case "SPECIAL":
			value, err := special(w[2], integer(w[3]))
			if err != nil { return nil, err }
			save(w[1], value)
		}
	}
	if deletion != "" { delete(c.names, deletion) }
	for _, item := range pending { c.names[item.name] = item.value }
	return output, nil
}

func main() {
	input := bufio.NewScanner(os.Stdin)
	if !input.Scan() { return }
	count := integer(input.Text())
	calculator := calculator{names: make(map[string]polynomial)}
	output := bufio.NewWriter(os.Stdout)
	defer output.Flush()
	for i := 0; i < count && input.Scan(); i++ {
		lines, err := calculator.process(input.Text())
		if err != nil { fmt.Fprintln(output, err); continue }
		for _, line := range lines { fmt.Fprintln(output, line) }
	}
}
