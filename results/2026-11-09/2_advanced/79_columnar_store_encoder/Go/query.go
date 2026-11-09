package main

import "strings"

type Literal struct {
	kind  string
	value Value
}
type Condition struct {
	op, column string
	index      int
	literals   []Literal
	children   []*Condition
}
type Item struct {
	op, column string
	distinct   bool
	index      int
}

func (i Item) header() string {
	if i.op == "" {
		return i.column
	}
	column := i.column
	if i.distinct {
		column = "DISTINCT " + column
	}
	return i.op + "(" + column + ")"
}

type Query struct {
	items        []Item
	star         bool
	condition    *Condition
	group, order string
	descending   bool
	limit        int
	aggregate    bool
	needed,
	conditionColumns, remaining []int
	groupIndex, orderIndex int
}
type QueryParser struct {
	tokens []string
	at     int
}

func queryTokens(s string) []string {
	var out []string
	for i := 0; i < len(s); {
		if s[i] == ' ' {
			i++
			continue
		}
		start := i
		c := s[i]
		if c == '\'' {
			i++
			for s[i] != '\'' {
				i++
			}
			i++
		} else if c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '-' {
			i++
			for i < len(s) {
				v := s[i]
				if !(v >= 'A' && v <= 'Z' || v >= 'a' && v <= 'z' || v >= '0' && v <= '9' || v == '_') {
					break
				}
				i++
			}
		} else {
			i++
			if i < len(s) && (c == '<' || c == '>') && (s[i] == '=' || s[i] == '>' && c == '<') {
				i++
			}
		}
		out = append(out,
			s[start:i])
	}
	return out
}
func (p *QueryParser) peek() string {
	if p.at == len(p.tokens) {
		return ""
	}
	return p.tokens[p.at]
}
func (p *QueryParser) take() string { s := p.tokens[p.at]; p.at++; return s }
func (p *QueryParser) literal() Literal {
	s := p.take()
	if s[0] == '\'' {
		return Literal{"STRING", Value{text: s[1 : len(s)-1]}}
	}
	if s == "TRUE" || s == "FALSE" {
		v := int64(0)
		if s == "TRUE" {
			v = 1
		}
		return Literal{"BOOL",
			Value{number: v}}
	}
	return Literal{"INT", Value{number: integer(s)}}
}
func (p *QueryParser) comparison() *Condition {
	column := p.take()
	op := p.take()
	c := &Condition{column: column,
		op: op, index: -1}
	switch op {
	case "IS":
		if p.peek() == "NOT" {
			p.take()
			c.op = "IS NOT NULL"
		} else {
			c.op = "IS NULL"
		}
		p.take()
	case "BETWEEN":
		c.literals = append(c.literals,
			p.literal())
		p.take()
		c.literals = append(c.literals, p.literal())
	case "IN":
		p.take()
		for {
			c.literals = append(c.literals,
				p.literal())
			if p.take() == ")" {
				break
			}
		}
	default:
		c.literals = append(c.literals, p.literal())
	}
	return c
}
func (p *QueryParser) negation() *Condition {
	if p.peek() == "NOT" {
		p.take()
		return &Condition{op: "NOT", children: []*Condition{p.negation()}}
	}
	if p.peek() == "(" {
		p.take()
		c := p.disjunction()
		p.take()
		return c
	}
	return p.comparison()
}
func (p *QueryParser) conjunction() *Condition {
	c := p.negation()
	for p.peek() == "AND" {
		p.take()
		c = &Condition{op: "AND", children: []*Condition{c, p.negation()}}
	}
	return c
}
func (p *QueryParser) disjunction() *Condition {
	c := p.conjunction()
	for p.peek() == "OR" {
		p.take()
		c = &Condition{op: "OR",
			children: []*Condition{c, p.conjunction()}}
	}
	return c
}
func parseQuery(text string) *Query {
	p := &QueryParser{tokens: queryTokens(text)}
	p.take()
	q := &Query{groupIndex: -1,
		orderIndex: -1}
	if p.peek() == "*" {
		p.take()
		q.star = true
	} else {
		for {
			token := p.take()
			item := Item{column: token,
				index: -1}
			if token == "COUNT" || token == "SUM" || token == "AVG" || token == "MIN" || token == "MAX" {
				q.aggregate = true
				item.op = token
				p.take()
				if p.peek() == "DISTINCT" {
					p.take()
					item.distinct = true
				}
				item.column = p.take()
				p.take()
			}
			q.items = append(q.items,
				item)
			if p.peek() != "," {
				break
			}
			p.take()
		}
	}
	if p.peek() == "WHERE" {
		p.take()
		q.condition = p.disjunction()
	}
	if p.peek() == "GROUP" {
		p.take()
		p.take()
		q.group = p.take()
		q.aggregate = true
	}
	if p.peek() == "ORDER" {
		p.take()
		p.take()
		q.order = p.take()
		if p.peek() == "ASC" || p.peek() == "DESC" {
			q.descending = p.take() == "DESC"
		}
	}
	if p.peek() == "LIMIT" {
		p.take()
		q.limit = number(p.take())
	}
	return q
}
func conditionLeaves(c *Condition) []*Condition {
	if c == nil {
		return nil
	}
	if len(c.children) == 0 {
		return []*Condition{c}
	}
	var out []*Condition
	for _, child := range c.children {
		out = append(out, conditionLeaves(child)...)
	}
	return out
}
func queryHeaders(q *Query) string {
	a := make([]string, len(q.items))
	for i, item := range q.items {
		a[i] = item.header()
	}
	return strings.Join(a, ",")
}
