package main

import "strings"

type Expr struct {
	op, name string
	value    Value
	args     []*Expr
}
type ExprParser struct {
	tokens []string
	at     int
}

func tokenize(s string) []string {
	var out []string
	for i := 0; i < len(s); {
		if s[i] == ' ' {
			i++
			continue
		}
		start := i
		c := s[i]
		if c == '"' {
			i++
			for s[i] != '"' {
				i++
			}
			i++
		} else if c >= '0' && c <= '9' {
			i++
			for i < len(s) && s[i] >= '0' && s[i] <= '9' {
				i++
			}
		} else if c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' {
			i++
			for i < len(s) {
				v := s[i]
				if !(v >= 'A' && v <= 'Z' || v >= 'a' && v <= 'z' || v >= '0' && v <= '9' || v == '_' || v == '.') {
					break
				}
				i++
			}
		} else {
			i++
			if i < len(s) && s[i] == '=' && strings.ContainsRune("=!<>",
				rune(c)) {
				i++
			}
		}
		out = append(out, s[start:i])
	}
	return out
}
func (p *ExprParser) peek() string {
	if p.at == len(p.tokens) {
		return ""
	}
	return p.tokens[p.at]
}
func (p *ExprParser) take() string { v := p.tokens[p.at]; p.at++; return v }
func (p *ExprParser) joined(next func() *Expr, ops ...string) *Expr {
	e := next()
	for {
		op := p.peek()
		found := false
		for _, v := range ops {
			if v == op {
				found = true
				break
			}
		}
		if !found {
			return e
		}
		p.take()
		e = &Expr{op: op, args: []*Expr{e,
			next()}}
	}
}
func (p *ExprParser) disjunction() *Expr { return p.joined(p.conjunction, "or") }
func (p *ExprParser) conjunction() *Expr { return p.joined(p.negation, "and") }
func (p *ExprParser) negation() *Expr {
	if p.peek() == "not" {
		p.take()
		return &Expr{op: "not", args: []*Expr{p.negation()}}
	}
	return p.comparison()
}
func (p *ExprParser) comparison() *Expr {
	e := p.sum()
	op := p.peek()
	if op == "==" || op == "!=" || op == "<" || op == "<=" || op == ">" || op == ">=" || op == "in" {
		p.take()
		return &Expr{op: op,
			args: []*Expr{e, p.sum()}}
	}
	return e
}
func (p *ExprParser) sum() *Expr     { return p.joined(p.product, "+", "-") }
func (p *ExprParser) product() *Expr { return p.joined(p.unary, "*") }
func (p *ExprParser) unary() *Expr {
	if p.peek() == "-" {
		p.take()
		return &Expr{op: "-", args: []*Expr{p.unary()}}
	}
	return p.primary()
}
func (p *ExprParser) primary() *Expr {
	token := p.take()
	if token == "(" {
		e := p.disjunction()
		p.take()
		return e
	}
	if token == "[" {
		var a []string
		for p.peek() != "]" {
			s := p.take()
			a = append(a,
				s[1:len(s)-1])
			if p.peek() != "]" {
				p.take()
			}
		}
		p.take()
		return &Expr{op: "literal", value: bagValue(a)}
	}
	if token[0] == '"' {
		return &Expr{op: "literal",
			value: stringValue(token[1 : len(token)-1])}
	}
	if token[0] >= '0' && token[0] <= '9' {
		return &Expr{op: "literal",
			value: intValue(number(token))}
	}
	if token == "true" || token == "false" {
		return &Expr{op: "literal", value: boolValue(token == "true")}
	}
	if token == "it" {
		return &Expr{op: "it"}
	}
	if strings.Contains(token,
		".") {
		return &Expr{op: "attribute", name: token}
	}
	p.take()
	var args []*Expr
	for p.peek() != ")" {
		args = append(args,
			p.disjunction())
		if p.peek() != ")" {
			p.take()
		}
	}
	p.take()
	return &Expr{op: token, args: args}
}
func parseExpr(s string) *Expr { return (&ExprParser{tokens: tokenize(s)}).disjunction() }
