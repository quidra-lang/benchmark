package main

import (
	"bufio"
	"fmt"
	"math"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

type commandError string
func fail(s string) {
	panic(commandError(s))
}
type Rational struct {
	P, Q int64
}
func rational(p, q int64) Rational {
	if q == 0 {
		fail("division by zero")
	};
	if q<0 {
		p, q = -p, -q
	};
	a, b := p, q;
	if a<0 {
		a = -a
	};
	for b != 0 {
		a, b = b, a%b
	};
	return Rational{p/a,q/a}
}
func (q Rational) add(b Rational) Rational {
	return rational(q.P*b.Q+b.P*q.Q, q.Q*b.Q)
}
func (q Rational) mul(b Rational) Rational {
	return rational(q.P*b.P, q.Q*b.Q)
}
func (q Rational) neg() Rational {
	return Rational{-q.P,q.Q}
}
type Expr struct {
	Kind int;
	Q Rational;
	Name string;
	Args []*Expr
}
func number(q Rational)*Expr {
	return &Expr{Kind:5,Q:q}
}
func num(p int64)*Expr {
	return number(rational(p, 1))
}
func node(k int, a []*Expr, s string)*Expr {
	return &Expr{Kind:k,Args:a,Name:s}
}
var zero, one, minus, half = num(0), num(1), num(-1), number(rational(1, 2))
var functions = map[string]bool{"sin":true,"cos":true,"tan":true,"exp":true,"ln":true,"sqrt":true}
func compare(a, b *Expr) int {
	if a.Kind != b.Kind {
		return a.Kind-b.Kind
	};
	if a.Kind == 5 {
		d := a.Q.P*b.Q.Q-b.Q.P*a.Q.Q;
		if d<0 {
			return -1
		};
		if d>0 {
			return 1
		};
		return 0
	}
	if a.Name != b.Name {
		return strings.Compare(a.Name, b.Name)
	};
	n := len(a.Args);
	if len(b.Args)<n {
		n = len(b.Args)
	};
	for i := 0; i<n; i++ {
		if c := compare(a.Args[i], b.Args[i]); c != 0 {
			return c
		}
	};
	return len(a.Args)-len(b.Args)
}
func equal(a, b *Expr) bool {
	return compare(a, b) == 0
}
func integer(f *Expr) bool {
	return f.Kind == 5 && f.Q.Q == 1
}
func negative(f *Expr) bool {
	return f.Kind == 3 && f.Args[1].Kind == 5 && f.Args[1].Q.P<0
}
func base(f *Expr)*Expr {
	if f.Kind == 3 {
		return f.Args[0]
	};
	return f
}
func exponent(f *Expr)*Expr {
	if f.Kind == 3 {
		return f.Args[1]
	};
	return one
}
func coefficient(f *Expr)(Rational, []*Expr) {
	if f.Kind == 5 {
		return f.Q, nil
	};
	if f.Kind == 2 {
		if f.Args[0].Kind == 5 {
			return f.Args[0].Q, f.Args[1:]
		};
		return rational(1, 1), f.Args
	};
	return rational(1, 1), []*Expr{f}
}
func product(c Rational, a []*Expr)*Expr {
	if len(a) == 0 {
		return number(c)
	};
	if c.P != c.Q {
		a = append([]*Expr{number(c)}, a...)
	};
	if len(a) == 1 {
		return a[0]
	};
	return node(2, a, "")
}
func exponentCompare(a, b *Expr) int {
	if a.Kind == 5 && b.Kind != 5 {
		return -1
	};
	if a.Kind != 5 && b.Kind == 5 {
		return 1
	};
	return compare(a, b)
}
func find(a []*Expr, b *Expr) int {
	for i, f := range a {
		if equal(f, b) {
			return i
		}
	};
	return -1
}
func termCompare(a, b *Expr) int {
	_, x := coefficient(a);
	_, y := coefficient(b);
	bases := []*Expr{};
	for _, list := range [][]*Expr{x,y} {
		for _, f := range list {
			v := base(f);
			if find(bases, v)<0 {
				bases = append(bases, v)
			}
		}
	};
	sort.Slice(bases, func (i, j int) bool {
		return compare(bases[i], bases[j])<0
	})
	for _, f := range bases {
		u, v := zero, zero;
		for _, t := range x {
			if equal(base(t), f) {
				u = exponent(t)
			}
		};
		for _, t := range y {
			if equal(base(t), f) {
				v = exponent(t)
			}
		};
		if c := exponentCompare(v, u); c != 0 {
			return c
		}
	};
	return 0
}
func add(operands ...*Expr)*Expr {
	terms := []*Expr{};
	for _, f := range operands {
		if f.Kind == 1 {
			terms = append(terms, f.Args...)
		} else if f.Kind == 2 && len(f.Args) == 2 && f.Args[0].Kind == 5 && f.Args[1].Kind == 1 {
			for _, t := range f.Args[1].Args {
				terms = append(terms, mul(f.Args[0], t))
			}
		} else {
			terms = append(terms, f)
		}
	}
	keys := [][]*Expr{};
	values := []Rational{};
	for _, f := range terms {
		c, m := coefficient(f);
		index := -1;
		for i, a := range keys {
			if len(a) != len(m) {
				continue
			};
			same := true;
			for j, t := range m {
				if !equal(t, a[j]) {
					same = false;
					break
				}
			};
			if same {
				index = i;
				break
			}
		};
		if index<0 {
			keys = append(keys, m);
			values = append(values, c)
		} else {
			values[index] = values[index].add(c)
		}
	}
	built := []*Expr{};
	for i, m := range keys {
		if values[i].P != 0 {
			built = append(built, product(values[i], m))
		}
	};
	sort.Slice(built, func (i, j int) bool {
		return termCompare(built[i], built[j])<0
	});
	if len(built) == 0 {
		return zero
	};
	if len(built) == 1 {
		return built[0]
	};
	return node(1, built, "")
}
func mul(operands ...*Expr)*Expr {
	c := rational(1, 1);
	bases := []*Expr{};
	groups := [][]*Expr{};
	factors := []*Expr{};
	for _, f := range operands {
		if f.Kind == 2 {
			factors = append(factors, f.Args...)
		} else {
			factors = append(factors, f)
		}
	}
	for _, f := range factors {
		if f.Kind == 5 {
			c = c.mul(f.Q)
		} else {
			b := base(f);
			i := find(bases, b);
			if i<0 {
				bases = append(bases, b);
				groups = append(groups, []*Expr{f})
			} else {
				groups[i] = append(groups[i], f)
			}
		}
	};
	if c.P == 0 {
		return zero
	}
	results := []*Expr{};
	for i, g := range groups {
		if len(g) == 1 {
			results = append(results, g[0])
		} else {
			xs := []*Expr{};
			for _, f := range g {
				xs = append(xs, exponent(f))
			};
			results = append(results, power(bases[i], add(xs...)))
		}
	}
	regroup := false;
	seen := []*Expr{};
	for _, f := range results {
		b := base(f);
		if f.Kind == 2 || f.Kind == 5 || find(seen, b) >= 0 {
			regroup = true
		};
		seen = append(seen, b)
	};
	if regroup {
		return mul(append([]*Expr{number(c)}, results...)...)
	};
	sort.Slice(results, func (i, j int) bool {
		return compare(base(results[i]), base(results[j]))<0
	});
	return product(c, results)
}
func root(v, d int64)(int64, bool) {
	if v == 1 {
		return 1, true
	};
	if d>20 {
		return 0, false
	};
	r := int64(math.Round(math.Pow(float64(v), 1/float64(d))));
	start := r-1;
	if start<0 {
		start = 0
	};
	for s := start; s <= r+1; s++ {
		a := int64(1);
		for i := int64(0); i<d && a <= v; i++ {
			a *= s
		};
		if a == v {
			return s, true
		}
	};
	return 0, false
}
func rationalPower(b Rational, n int64)*Expr {
	if n<0 {
		b = rational(b.Q, b.P);
		n = -n
	};
	r := rational(1, 1);
	for n>0 {
		if n%2 != 0 {
			r = r.mul(b)
		};
		n /= 2;
		if n>0 {
			b = b.mul(b)
		}
	};
	return number(r)
}
func power(b, x *Expr)*Expr {
	if equal(x, zero) {
		return one
	};
	if equal(x, one) {
		return b
	};
	if b.Kind == 5 {
		if equal(b, one) {
			return one
		};
		if x.Kind != 5 {
			return node(3, []*Expr{b,x}, "")
		};
		if b.Q.P == 0 {
			if x.Q.P>0 {
				return zero
			};
			fail("division by zero")
		};
		if integer(x) {
			return rationalPower(b.Q, x.Q.P)
		};
		if b.Q.P>0 {
			s, ok := root(b.Q.P, x.Q.Q);
			t, ok2 := root(b.Q.Q, x.Q.Q);
			if ok && ok2 {
				return rationalPower(rational(s, t), x.Q.P)
			}
		}
	} else if integer(x) {
		if b.Kind == 3 {
			return power(b.Args[0], mul(b.Args[1], x))
		};
		if b.Kind == 2 {
			a := []*Expr{};
			for _, f := range b.Args {
				a = append(a, power(f, x))
			};
			return mul(a...)
		}
	};
	return node(3, []*Expr{b,x}, "")
}
func fn(s string, a *Expr)*Expr {
	if s == "sqrt" {
		return power(a, half)
	};
	if equal(a, zero) && (s == "sin" || s == "tan") {
		return zero
	};
	if equal(a, zero) && (s == "cos" || s == "exp") {
		return one
	};
	if equal(a, one) && s == "ln" {
		return zero
	};
	c, _ := coefficient(a);
	if (s == "sin" || s == "cos" || s == "tan") && c.P<0 {
		r := fn(s, mul(minus, a));
		if s == "cos" {
			return r
		};
		return mul(minus, r)
	};
	if a.Kind == 4 && ((s == "exp" && a.Name == "ln") || (s == "ln" && a.Name == "exp")) {
		return a.Args[0]
	};
	return node(4, []*Expr{a}, s)
}
func variables(f *Expr)[]string {
	seen := map[string]bool{};
	var visit func (*Expr);
	visit = func (f *Expr) {
		if f.Kind == 0 {
			seen[f.Name] = true
		};
		for _, a := range f.Args {
			visit(a)
		}
	};
	visit(f);
	r := []string{};
	for s := range seen {
		r = append(r, s)
	};
	sort.Strings(r);
	return r
}
func contains(a []string, v string) bool {
	for _, s := range a {
		if s == v {
			return true
		}
	};
	return false
}
func derivative(f *Expr, v string)*Expr {
	if f.Kind == 5 {
		return zero
	};
	if f.Kind == 0 {
		if f.Name == v {
			return one
		};
		return zero
	};
	if f.Kind == 1 {
		a := []*Expr{};
		for _, t := range f.Args {
			a = append(a, derivative(t, v))
		};
		return add(a...)
	};
	if f.Kind == 2 {
		a := []*Expr{};
		for i, t := range f.Args {
			p := append([]*Expr{}, f.Args...);
			p[i] = derivative(t, v);
			a = append(a, mul(p...))
		};
		return add(a...)
	}
	if f.Kind == 3 {
		b, x := f.Args[0], f.Args[1];
		if !contains(variables(x), v) {
			return mul(x, power(b, add(x, minus)), derivative(b, v))
		};
		if !contains(variables(b), v) {
			return mul(f, fn("ln", b), derivative(x, v))
		};
		return mul(f, add(mul(derivative(x, v), fn("ln", b)), mul(x, derivative(b, v), power(b, minus))))
	};
	a := f.Args[0];
	var h *Expr;
	switch f.Name {
		case "sin":h = fn("cos", a);
		case "cos":h = mul(minus, fn("sin", a));
		case "tan":h = power(fn("cos", a), num(-2));
		case "exp":h = f;
		default:h = power(a, minus)
	};
	return mul(h, derivative(a, v))
}
func rebuild(f *Expr, a []*Expr)*Expr {
	switch f.Kind {
		case 1:return add(a...);
		case 2:return mul(a...);
		case 3:return power(a[0], a[1]);
		default:return fn(f.Name, a[0])
	}
}
func substitute(f *Expr, m map[string]*Expr)*Expr {
	if f.Kind == 0 {
		if r, ok := m[f.Name]; ok {
			return r
		};
		return f
	};
	if f.Kind == 5 {
		return f
	};
	a := []*Expr{};
	for _, t := range f.Args {
		a = append(a, substitute(t, m))
	};
	return rebuild(f, a)
}
func terms(f *Expr)[]*Expr {
	if f.Kind == 1 {
		return f.Args
	};
	return []*Expr{f}
}
func distribute(a, b *Expr)*Expr {
	r := []*Expr{};
	for _, x := range terms(a) {
		for _, y := range terms(b) {
			r = append(r, mul(x, y))
		}
	};
	return add(r...)
}
func expand(f *Expr)*Expr {
	if f.Kind == 0 || f.Kind == 5 {
		return f
	};
	a := []*Expr{};
	for _, t := range f.Args {
		a = append(a, expand(t))
	};
	if f.Kind == 2 {
		r := a[0];
		for _, t := range a[1:]{r=distribute(r,t)}; return r
	};
	if f.Kind == 3 && a[0].Kind == 1 && integer(a[1]) && a[1].Q.P>0 {
		r := a[0];
		for i := int64(1); i<a[1].Q.P; i++ {
			r = distribute(r, a[0])
		};
		return r
	};
	return rebuild(f, a)
}
func numeric(f *Expr) float64 {
	if f.Kind == 5 {
		return float64(f.Q.P)/float64(f.Q.Q)
	};
	if f.Kind == 1 || f.Kind == 2 {
		r := 0.0;
		if f.Kind == 2 {
			r = 1
		};
		for _, t := range f.Args {
			a := numeric(t);
			if f.Kind == 1 {
				r += a
			} else {
				r *= a
			}
		};
		return r
	};
	if f.Kind == 3 {
		u, z := numeric(f.Args[0]), numeric(f.Args[1]);
		integral := z == math.Trunc(z);
		if f.Args[1].Kind == 5 {
			integral = integer(f.Args[1])
		};
		if u<0 && !integral {
			fail("domain error")
		};
		if equal(f.Args[1], half) {
			return math.Sqrt(u)
		};
		return math.Pow(u, z)
	};
	a := numeric(f.Args[0]);
	switch f.Name {
		case "sin":return math.Sin(a);
		case "cos":return math.Cos(a);
		case "tan":return math.Tan(a);
		case "exp":return math.Exp(a);
		default:if a <= 0 {
			fail("domain error")
		};
		return math.Log(a)
	}
}
func atomic(f *Expr) bool {
	return f.Kind == 0 || f.Kind == 4 || (integer(f) && f.Q.P >= 0) || (f.Kind == 3 && equal(f.Args[1], half))
}
func atom(f *Expr) string {
	if atomic(f) {
		return show(f)
	};
	return "("+show(f)+")"
}
func showPower(b, x *Expr) string {
	if equal(x, half) {
		return "sqrt("+show(b)+")"
	};
	return atom(b)+"^"+atom(x)
}
func factor(f *Expr) string {
	if f.Kind == 1 {
		return "("+show(f)+")"
	};
	if f.Kind == 3 {
		return showPower(f.Args[0], f.Args[1])
	};
	return show(f)
}
func quotient(c Rational, a []*Expr) string {
	p := c.P;
	if p<0 {
		p = -p
	};
	top, bottom := []string{}, []string{};
	if p != 1 {
		top = append(top, strconv.FormatInt(p, 10))
	};
	if c.Q != 1 {
		bottom = append(bottom, strconv.FormatInt(c.Q, 10))
	};
	for _, f := range a {
		if negative(f) {
			r := number(f.Args[1].Q.neg());
			if equal(r, one) {
				bottom = append(bottom, factor(f.Args[0]))
			} else {
				bottom = append(bottom, showPower(f.Args[0], r))
			}
		} else {
			top = append(top, factor(f))
		}
	};
	s := strings.Join(top, "*");
	if s == "" {
		s = "1"
	};
	if len(bottom) == 1 {
		s += "/"+bottom[0]
	} else if len(bottom)>1 {
		s += "/("+strings.Join(bottom, "*")+")"
	};
	if c.P<0 {
		s = "-"+s
	};
	return s
}
func show(f *Expr) string {
	if f.Kind == 5 {
		s := strconv.FormatInt(f.Q.P, 10);
		if f.Q.Q != 1 {
			s += "/"+strconv.FormatInt(f.Q.Q, 10)
		};
		return s
	};
	if f.Kind == 0 {
		return f.Name
	};
	if f.Kind == 4 {
		return f.Name+"("+show(f.Args[0])+")"
	};
	if f.Kind == 3 {
		if negative(f) {
			return quotient(rational(1, 1), []*Expr{f})
		};
		return showPower(f.Args[0], f.Args[1])
	};
	if f.Kind == 2 {
		c, a := coefficient(f);
		return quotient(c, a)
	};
	s := show(f.Args[0]);
	for _, t := range f.Args[1:]{part:=show(t);if strings.HasPrefix(part,"-"){s+=" - "+part[1:]}else{s+=" + "+part}}; return s
}
type syntax struct {
	Op string;
	Value *Expr;
	Args []*syntax
}
type parser struct {
	Tokens []string;
	Position int;
	Names map[string]*Expr
}
func digit(c byte) bool {
	return c >= '0' && c <= '9'
}
func lower(c byte) bool {
	return c >= 'a' && c <= 'z'
}
func upper(c byte) bool {
	return c >= 'A' && c <= 'Z'
}
func newParser(text string, names map[string]*Expr)*parser {
	p := &parser{Names:names};
	for i := 0; i<len(text); {
		c := text[i];
		if c == ' ' {
			i++;
			continue
		};
		start := i;
		i++;
		if digit(c) {
			for i<len(text) && digit(text[i]) {
				i++
			}
		} else if lower(c) {
			for i<len(text) && (lower(text[i]) || digit(text[i])) {
				i++
			}
		} else if upper(c) {
			for i<len(text) && (upper(text[i]) || digit(text[i])) {
				i++
			}
		} else if !strings.ContainsRune("+-*/^()", rune(c)) {
			fail(fmt.Sprintf("invalid character '%c'", c))
		};
		p.Tokens = append(p.Tokens, text[start:i])
	};
	return p
}
func (p *parser) peek() string {
	if p.Position<len(p.Tokens) {
		return p.Tokens[p.Position]
	};
	return ""
}
func (p *parser) unexpected() {
	if p.Position == len(p.Tokens) {
		fail("unexpected end of expression")
	};
	fail("unexpected '"+p.peek()+"'")
}
func (p *parser) accept(s string) bool {
	if p.peek() != s {
		return false
	};
	p.Position++;
	return true
}
func (p *parser) expect(s string) {
	if !p.accept(s) {
		p.unexpected()
	}
}
func (p *parser) atom()*syntax {
	t := p.peek();
	if t == "" {
		p.unexpected()
	};
	if p.accept("(") {
		a := p.expression();
		p.expect(")");
		return a
	};
	c := t[0];
	if !digit(c) && !lower(c) && !upper(c) {
		p.unexpected()
	};
	p.Position++;
	if digit(c) {
		v, _ := strconv.ParseInt(t, 10, 64);
		return &syntax{Value:num(v)}
	};
	if upper(c) {
		f, ok := p.Names[t];
		if !ok {
			fail("undefined name '"+t+"'")
		};
		return &syntax{Value:f}
	};
	if !functions[t]{return &syntax{Value:node(0,nil,t)}}; p.expect("("); a := p.expression(); p.expect(")"); return &syntax{Op:t,Args:[]*syntax{a}}
}
func (p *parser) unary()*syntax {
	if p.accept("-") {
		return &syntax{Op:"neg",Args:[]*syntax{p.unary()}}
	};
	a := p.atom();
	if p.accept("^") {
		return &syntax{Op:"^",Args:[]*syntax{a,p.unary()}}
	};
	return a
}
func (p *parser) term()*syntax {
	a := p.unary();
	for p.peek() == "*" || p.peek() == "/" {
		op := p.Tokens[p.Position];
		p.Position++;
		a = &syntax{Op:op,Args:[]*syntax{a,p.unary()}}
	};
	return a
}
func (p *parser) expression()*syntax {
	a := p.term();
	for p.peek() == "+" || p.peek() == "-" {
		op := p.Tokens[p.Position];
		p.Position++;
		a = &syntax{Op:op,Args:[]*syntax{a,p.term()}}
	};
	return a
}
func evaluate(t *syntax)*Expr {
	if t.Value != nil {
		return t.Value
	};
	a := []*Expr{};
	for _, s := range t.Args {
		a = append(a, evaluate(s))
	};
	switch t.Op {
		case "+":return add(a...);
		case "-":return add(a[0], mul(minus, a[1]));
		case "*":return mul(a...);
		case "/":return mul(a[0], power(a[1], minus));
		case "^":return power(a[0], a[1]);
		case "neg":return mul(minus, a[0]);
		default:return fn(t.Op, a[0])
	}
}
func parse(text string, names map[string]*Expr)*Expr {
	p := newParser(text, names);
	t := p.expression();
	if p.Position<len(p.Tokens) {
		p.unexpected()
	};
	return evaluate(t)
}
var variablePattern = regexp.MustCompile(`^[a-z][a-z0-9]*$`)
var literalPattern = regexp.MustCompile(`^-?[0-9]+(?:/[0-9]+)?$`)
var namePattern = regexp.MustCompile(`^[A-Z][A-Z0-9]*$`)
func variable(s string) bool {
	return variablePattern.MatchString(s) && !functions[s]
}
func literal(s string)*Expr {
	if !literalPattern.MatchString(s) {
		fail("invalid number '"+s+"'")
	};
	a := strings.Split(s, "/");
	p, _ := strconv.ParseInt(a[0], 10, 64);
	q := int64(1);
	if len(a) == 2 {
		q, _ = strconv.ParseInt(a[1], 10, 64)
	};
	return number(rational(p, q))
}
var signatures = map[string]string{"SIMPLIFY":"e","EXPAND":"e","DIFF":"ev","DIFFN":"evn","GRAD":"e","HESSIAN":"e","IMPLICIT":"evv","SUBST":"eve","EVAL":"ea","TANGENT":"evc","LIMIT":"evc","TAYLOR":"evcn"}
func command(line string, names map[string]*Expr)[]string {
	c, arg, has := strings.Cut(line, " ");
	if c == "LET" {
		s, text, ok := strings.Cut(arg, "=");
		if !ok {
			fail("wrong number of arguments")
		};
		s = strings.Trim(s, " ");
		if !namePattern.MatchString(s) {
			fail("invalid name '"+s+"'")
		};
		f := parse(strings.Trim(text, " "), names);
		names[s] = f;
		return []string{s+" = "+show(f)}
	};
	sig, ok := signatures[c];
	if !ok {
		fail("unknown command "+c)
	};
	fields := []string{};
	if has {
		fields = strings.Split(arg, ";");
		for i := range fields {
			fields[i] = strings.Trim(fields[i], " ")
		}
	};
	valid := len(fields) == len(sig);
	if c == "EVAL" {
		valid = len(fields) == 1 || len(fields) == 2
	};
	if !valid {
		fail("wrong number of arguments")
	}
	forms := make([]*Expr, len(fields));
	n := 0;
	for i, s := range fields {
		forms[i] = zero;
		switch sig[i]{case 'e':forms[i]=parse(s,names);case 'v':if !variable(s){fail("invalid variable '"+s+"'")};case 'n':if len(s)!=1||s[0]<'1'||s[0]>'8'{fail("invalid order '"+s+"'")};n=int(s[0]-'0');case 'c':forms[i]=literal(s)}
	};
	f := forms[0];
	v := "";
	if len(fields)>1 {
		v = fields[1]
	};
	out := []string{}
	switch c {
		case "SIMPLIFY":return []string{"simplified: "+show(f)};
		case "EXPAND":return []string{"expanded: "+show(expand(f))};
		case "DIFF":return []string{"d/d"+v+" = "+show(derivative(f,v))};
		case "DIFFN":for k := 1; k <= n; k++ {
			f = derivative(f, v);
			out = append(out, fmt.Sprintf("d^%d/d%s^%d = %s", k, v, k, show(f)))
		};
		return out;
		case "GRAD", "HESSIAN":vs := variables(f);
		if len(vs) == 0 {
			return []string{"no variables"}
		};
		for i, s := range vs {
			d := derivative(f, s);
			if c == "GRAD" {
				out = append(out, "d/d"+s+" = "+show(d))
			} else {
				for _, t := range vs[i:]{out=append(out,"d2/d"+s+"d"+t+" = "+show(derivative(d,t)))}
			}
		};
		return out;
		case "IMPLICIT":w := fields[2];
		if v == w {
			fail("same variable")
		};
		return []string{"d"+w+"/d"+v+" = "+show(mul(minus,derivative(f,v),power(derivative(f,w),minus)))};
		case "SUBST":return []string{"substituted: "+show(substitute(f,map[string]*Expr{v:forms[2]}))};
		case "EVAL":values := map[string]*Expr{};
		for _, word := range strings.Fields(v) {
			s, t, ok := strings.Cut(word, "=");
			if !ok || !variable(s) || !literalPattern.MatchString(t) {
				fail("invalid assignment '"+word+"'")
			};
			q := literal(t);
			if _, ok := values[s]; ok {
				fail("duplicate variable "+s)
			};
			values[s] = q
		};
		for _, s := range variables(f) {
			if _, ok := values[s]; !ok {
				fail("no value for "+s)
			}
		};
		r := substitute(f, values);
		if r.Kind == 5 {
			return []string{"exact: "+show(r)}
		};
		return []string{fmt.Sprintf("approx: %.6f",numeric(r))}
	}
	x := forms[2];
	point := map[string]*Expr{v:x};
	if c == "TANGENT" {
		m := substitute(derivative(f, v), point);
		y := substitute(f, point);
		z := node(0, nil, v);
		t := "tangent: y = "+show(add(mul(m, z), y, mul(number(x.Q.neg()), m)));
		if equal(m, zero) {
			return []string{t,"normal: "+v+" = "+show(x)}
		};
		k := power(m, minus);
		return []string{t,"normal: y = "+show(add(mul(minus,k,z),y,mul(x,k)))}
	};
	if c == "LIMIT" {
		top, bottom := []*Expr{}, []*Expr{};
		factors := []*Expr{f};
		if f.Kind == 2 {
			factors = f.Args
		};
		for _, t := range factors {
			if negative(t) {
				bottom = append(bottom, power(t.Args[0], number(t.Args[1].Q.neg())))
			} else {
				top = append(top, t)
			}
		};
		g, h := mul(top...), mul(bottom...);
		for k := 0; k <= 5; k++ {
			a := substitute(g, point);
			b := substitute(h, point);
			if !equal(b, zero) {
				return []string{"limit: "+show(mul(a,power(b,minus)))}
			};
			if !equal(a, zero) {
				return []string{"limit: unbounded"}
			};
			if k<5 {
				g = derivative(g, v);
				h = derivative(h, v)
			}
		};
		return []string{"limit: unknown"}
	};
	ds, ps := []*Expr{f}, []*Expr{};
	for i := 0; i<n; i++ {
		ds = append(ds, derivative(ds[len(ds)-1], v))
	};
	fac := int64(1);
	for k := 0; k <= n; k++ {
		if k>0 {
			fac *= int64(k)
		};
		co := mul(substitute(ds[k], point), number(rational(1, fac)));
		ps = append(ps, mul(co, power(add(node(0, nil, v), number(x.Q.neg())), num(int64(k)))))
	};
	return []string{"taylor: "+show(expand(add(ps...)))}
}
func execute(line string, names map[string]*Expr)(out []string) {
	defer func () {
		if e := recover(); e != nil {
			if s, ok := e.(commandError); ok {
				out = []string{"error: "+string(s)}
			} else {
				panic(e)
			}
		}
	}();
	return command(line, names)
}
func main() {
	input := bufio.NewScanner(os.Stdin);
	input.Scan();
	n, _ := strconv.Atoi(input.Text());
	names := map[string]*Expr{};
	out := bufio.NewWriter(os.Stdout);
	defer out.Flush();
	for i := 0; i<n && input.Scan(); i++ {
		for _, line := range execute(input.Text(), names) {
			fmt.Fprintln(out, line)
		}
	}
}
