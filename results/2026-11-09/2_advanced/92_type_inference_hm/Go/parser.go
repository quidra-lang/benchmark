package main

type Expr struct {
	Kind, Value string
	Position
	Integer  int64
	Children []*Expr
	Token    Token
	Group    *Group
	Arms     []Arm
	Inferred *Type
}
type Arm struct{ Pattern, Body *Expr }
type Binding struct {
	Name           Token
	Expr           *Expr
	Scheme         Scheme
	Classification string
}
type Group struct {
	Bindings []*Binding
	Rec      *Position
}
type Item struct {
	Kind     string
	Name     Token
	Declared *Expr
	Group    *Group
	Expr     *Expr
}
type SyntaxError struct{ Token Token }
type Parser struct {
	Tokens []Token
	Index  int
}

func (p *Parser) peek() Token { return p.Tokens[p.Index] }
func (p *Parser) accept(kind string) (Token, bool) {
	t := p.peek()
	if t.Kind != kind {
		return Token{}, false
	}
	p.Index++
	return t, true
}
func (p *Parser) expect(kind string) Token {
	if t, ok := p.accept(kind); ok {
		return t
	}
	panic(&SyntaxError{p.peek()})
}
func (p *Parser) name() Token {
	if !p.peek().name() {
		panic(&SyntaxError{p.peek()})
	}
	return p.expect("identifier")
}
func (p *Parser) recoverItem() {
	for p.peek().Kind != ";;" && p.peek().Kind != "EOF" {
		p.Index++
	}
	p.accept(";;")
}
func (p *Parser) item() *Item {
	if _, ok := p.accept("val"); ok {
		name := p.name()
		p.expect(":")
		declared := p.typeExpression()
		p.expect(";;")
		return &Item{Kind: "signature", Name: name, Declared: declared}
	}
	var item *Item
	if opening, ok := p.accept("let"); ok {
		g := p.group()
		if _, yes := p.accept("in"); yes {
			item = &Item{Kind: "expression", Expr: &Expr{Kind: "let", Position: opening.Position, Group: g, Children: []*Expr{p.expression()}}}
		} else {
			item = &Item{Kind: "declaration", Group: g}
		}
	} else {
		item = &Item{Kind: "expression", Expr: p.expression()}
	}
	p.expect(";;")
	return item
}
func (p *Parser) readItem() (item *Item, failure *SyntaxError) {
	defer func() {
		if value := recover(); value != nil {
			if err, ok := value.(*SyntaxError); ok {
				failure = err
			} else {
				panic(value)
			}
		}
	}()
	item = p.item()
	return
}
func (p *Parser) group() *Group {
	g := &Group{}
	if rec, ok := p.accept("rec"); ok {
		position := rec.Position
		g.Rec = &position
	}
	g.Bindings = append(g.Bindings, p.binding())
	for {
		if _, ok := p.accept("and"); !ok {
			break
		}
		g.Bindings = append(g.Bindings, p.binding())
	}
	return g
}
func (p *Parser) binding() *Binding {
	name := p.name()
	parameters := []Token{}
	for p.peek().Kind == "identifier" {
		parameters = append(parameters, p.expect("identifier"))
	}
	p.expect("=")
	e := p.expression()
	for i := len(parameters) - 1; i >= 0; i-- {
		e = &Expr{Kind: "fun", Position: parameters[i].Position, Token: parameters[i], Children: []*Expr{e}}
	}
	return &Binding{Name: name, Expr: e}
}
func operator(op string) (int, bool) {
	switch op {
	case "||":
		return 1, true
	case "&&":
		return 2, true
	case "=", "<>", "<", ">", "<=", ">=":
		return 3, false
	case "::", "^":
		return 4, true
	case "+", "-":
		return 5, false
	case "*", "/", "mod":
		return 6, false
	}
	return 0, false
}
func (p *Parser) expression() *Expr {
	if opening, ok := p.accept("let"); ok {
		g := p.group()
		p.expect("in")
		return &Expr{Kind: "let", Position: opening.Position, Group: g, Children: []*Expr{p.expression()}}
	}
	if opening, ok := p.accept("fun"); ok {
		parameters := []Token{p.expect("identifier")}
		for p.peek().Kind == "identifier" {
			parameters = append(parameters, p.expect("identifier"))
		}
		p.expect("->")
		e := p.expression()
		for i := len(parameters) - 1; i >= 0; i-- {
			e = &Expr{Kind: "fun", Position: parameters[i].Position, Token: parameters[i], Children: []*Expr{e}}
		}
		e.Position = opening.Position
		return e
	}
	if opening, ok := p.accept("if"); ok {
		condition := p.expression()
		p.expect("then")
		first := p.expression()
		p.expect("else")
		second := p.expression()
		return &Expr{Kind: "if", Position: opening.Position, Children: []*Expr{condition, first, second}}
	}
	if opening, ok := p.accept("match"); ok {
		e := p.expression()
		p.expect("with")
		p.accept("|")
		arms := []Arm{p.arm()}
		for {
			if _, yes := p.accept("|"); !yes {
				break
			}
			arms = append(arms, p.arm())
		}
		return &Expr{Kind: "match", Position: opening.Position, Children: []*Expr{e}, Arms: arms}
	}
	return p.binary(1)
}
func (p *Parser) arm() Arm {
	pattern := p.pattern()
	p.expect("->")
	return Arm{pattern, p.expression()}
}
func (p *Parser) binary(minimum int) *Expr {
	left := p.unary()
	for {
		precedence, rightAssociative := operator(p.peek().Kind)
		if precedence == 0 || precedence < minimum {
			break
		}
		op := p.peek()
		p.Index++
		next := precedence + 1
		if rightAssociative {
			next = precedence
		}
		right := p.binary(next)
		left = &Expr{Kind: "binary", Position: left.Position, Token: op, Children: []*Expr{left, right}}
	}
	return left
}
func startsAtom(t Token) bool { return wordIn("integer string true false ( [", t.Kind) || t.name() }
func (p *Parser) unary() *Expr {
	if op, ok := p.accept("-"); ok {
		return &Expr{Kind: "negate", Position: op.Position, Token: op, Children: []*Expr{p.unary()}}
	}
	e := p.atom()
	for startsAtom(p.peek()) {
		e = &Expr{Kind: "apply", Position: e.Position, Children: []*Expr{e, p.atom()}}
	}
	return e
}
func (p *Parser) atom() *Expr {
	t := p.peek()
	if t.Kind == "integer" || t.Kind == "string" {
		p.Index++
		return &Expr{Kind: t.Kind, Position: t.Position, Value: t.Value, Integer: t.Integer}
	}
	if t.Kind == "true" || t.Kind == "false" {
		p.Index++
		return &Expr{Kind: "boolean", Position: t.Position, Value: t.Kind}
	}
	if t.name() {
		p.Index++
		return &Expr{Kind: "name", Position: t.Position, Value: t.Spelling}
	}
	if _, ok := p.accept("("); ok {
		first := p.expression()
		if _, yes := p.accept(","); yes {
			second := p.expression()
			p.expect(")")
			return &Expr{Kind: "pair", Position: t.Position, Children: []*Expr{first, second}}
		}
		p.expect(")")
		return first
	}
	if _, ok := p.accept("["); ok {
		elements := []*Expr{}
		if _, yes := p.accept("]"); !yes {
			elements = append(elements, p.expression())
			for {
				if _, yes := p.accept(";"); !yes {
					break
				}
				elements = append(elements, p.expression())
			}
			p.expect("]")
		}
		return &Expr{Kind: "list", Position: t.Position, Children: elements}
	}
	panic(&SyntaxError{t})
}
func (p *Parser) pattern() *Expr {
	first := p.patternAtom()
	if _, ok := p.accept("::"); ok {
		return &Expr{Kind: "cons", Position: first.Position, Children: []*Expr{first, p.pattern()}}
	}
	return first
}
func (p *Parser) patternAtom() *Expr {
	t := p.peek()
	if t.Kind == "identifier" {
		p.Index++
		kind := "name"
		if t.Spelling == "_" {
			kind = "wildcard"
		}
		return &Expr{Kind: kind, Position: t.Position, Value: t.Spelling}
	}
	if _, ok := p.accept("-"); ok {
		number := p.expect("integer")
		return &Expr{Kind: "integer", Position: t.Position, Integer: -number.Integer}
	}
	if wordIn("integer string true false", t.Kind) {
		return p.atom()
	}
	if _, ok := p.accept("("); ok {
		first := p.pattern()
		if _, yes := p.accept(","); yes {
			second := p.pattern()
			p.expect(")")
			return &Expr{Kind: "pair", Position: t.Position, Children: []*Expr{first, second}}
		}
		p.expect(")")
		return first
	}
	if _, ok := p.accept("["); ok {
		elements := []*Expr{}
		if _, yes := p.accept("]"); !yes {
			elements = append(elements, p.pattern())
			for {
				if _, yes := p.accept(";"); !yes {
					break
				}
				elements = append(elements, p.pattern())
			}
			p.expect("]")
		}
		return &Expr{Kind: "list", Position: t.Position, Children: elements}
	}
	panic(&SyntaxError{t})
}
func (p *Parser) typeExpression() *Expr {
	first := p.listType()
	if _, ok := p.accept("*"); ok {
		first = &Expr{Kind: "pair", Position: first.Position, Children: []*Expr{first, p.listType()}}
	}
	if _, ok := p.accept("->"); ok {
		first = &Expr{Kind: "function", Position: first.Position, Children: []*Expr{first, p.typeExpression()}}
	}
	return first
}
func (p *Parser) listType() *Expr {
	e := p.typeAtom()
	for p.peek().Kind == "identifier" && p.peek().Spelling == "list" {
		p.Index++
		e = &Expr{Kind: "list", Position: e.Position, Children: []*Expr{e}}
	}
	return e
}
func (p *Parser) typeAtom() *Expr {
	t := p.peek()
	if t.Kind == "identifier" && wordIn("int bool string", t.Spelling) {
		p.Index++
		return &Expr{Kind: t.Spelling, Position: t.Position}
	}
	if _, ok := p.accept("type_variable"); ok {
		return &Expr{Kind: "type_variable", Position: t.Position, Value: t.Spelling}
	}
	if _, ok := p.accept("("); ok {
		e := p.typeExpression()
		p.expect(")")
		return e
	}
	panic(&SyntaxError{t})
}
