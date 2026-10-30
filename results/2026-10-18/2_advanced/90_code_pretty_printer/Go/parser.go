package main

type Node struct {
	Kind, Value                                                 string
	First, Last                                                 int
	Token, Name, Open, Close, Op, Colon, ElseToken, Semi, Semi2 *Token
	Expr, Left, Right, Then, Else, Body, Init, Cond, Update     *Node
	Elements, Dimensions                                        []*Node
	Commas                                                      []*Token
	Trailing                                                    *Token
}

func nodeChildren(n *Node) []*Node {
	out := []*Node{}
	for _, child := range []*Node{n.Expr, n.Left, n.Right, n.Then, n.Else, n.Body, n.Init, n.Cond, n.Update} {
		if child != nil {
			out = append(out, child)
		}
	}
	out = append(out, n.Elements...)
	out = append(out, n.Dimensions...)
	return out
}
func typeName(t *Token) bool { return wordIn("int float bool string void", t.Text) }
func precedence(op string) int {
	switch op {
	case "||":
		return 1
	case "&&":
		return 2
	case "==", "!=":
		return 3
	case "<", "<=", ">", ">=":
		return 4
	case "+", "-":
		return 5
	case "*", "/", "%":
		return 6
	}
	return 0
}
func expressionLevel(n *Node) int {
	switch n.Kind {
	case "conditional":
		return 0
	case "binary":
		return precedence(n.Op.Text)
	case "unary":
		return 7
	}
	return 8
}

type Parser struct {
	Tokens   []*Token
	Position int
	Err      *FileError
}

func (p *Parser) peek() *Token { return p.Tokens[min(p.Position, len(p.Tokens)-1)] }
func (p *Parser) read() *Token {
	t := p.peek()
	if p.Position < len(p.Tokens)-1 {
		p.Position++
	}
	return t
}
func (p *Parser) fail(expected string) {
	if p.Err != nil {
		return
	}
	t := p.peek()
	actual := "end of file"
	if t.Kind != "end" {
		actual = "'" + t.Text + "'"
	}
	p.Err = &FileError{t.Position, "expected " + expected + ", found " + actual}
}
func (p *Parser) take(text string) *Token {
	if p.peek().Text != text {
		p.fail("'" + text + "'")
		return p.peek()
	}
	return p.read()
}
func (p *Parser) takeType() *Token {
	if !typeName(p.peek()) {
		p.fail("type")
		return p.peek()
	}
	return p.read()
}
func (p *Parser) identifier() *Token {
	if p.peek().Kind != "identifier" {
		p.fail("identifier")
		return p.peek()
	}
	return p.read()
}
func (p *Parser) mark(n *Node, start int) *Node {
	n.First = start
	n.Last = max(start, p.Position-1)
	return n
}
func (p *Parser) program() *Node {
	n := &Node{Kind: "program"}
	for p.Err == nil && p.peek().Kind != "end" {
		start := p.Position
		t, name := p.takeType(), p.identifier()
		if p.Err != nil {
			break
		}
		if p.peek().Text == "(" {
			params := p.list("parameters", "(", ")", false)
			body := p.block()
			n.Elements = append(n.Elements, p.mark(&Node{Kind: "function", Token: t, Name: name, Init: params, Body: body}, start))
		} else {
			n.Elements = append(n.Elements, p.declaration(t, name, start, true))
		}
	}
	return n
}
func (p *Parser) list(kind, open, close string, trailing bool) *Node {
	start := p.Position
	n := &Node{Kind: "list", Value: kind, Open: p.take(open)}
	if p.peek().Text != close && p.Err == nil {
		for p.Err == nil {
			var child *Node
			switch kind {
			case "parameters":
				child = p.parameter()
			case "initializer":
				child = p.initializer()
			default:
				child = p.expression()
			}
			n.Elements = append(n.Elements, child)
			if p.peek().Text != "," {
				break
			}
			comma := p.read()
			if trailing && p.peek().Text == close {
				n.Trailing = comma
				break
			}
			n.Commas = append(n.Commas, comma)
		}
	}
	n.Close = p.take(close)
	return p.mark(n, start)
}
func (p *Parser) parameter() *Node {
	start := p.Position
	n := &Node{Kind: "parameter", Token: p.takeType(), Name: p.identifier()}
	for p.Err == nil && p.peek().Text == "[" {
		dstart := p.Position
		open := p.read()
		close := p.take("]")
		n.Dimensions = append(n.Dimensions, p.mark(&Node{Kind: "dimension", Open: open, Close: close}, dstart))
	}
	return p.mark(n, start)
}
func (p *Parser) declaration(t, name *Token, start int, semi bool) *Node {
	n := &Node{Kind: "declaration", Token: t, Name: name}
	for p.Err == nil && p.peek().Text == "[" {
		dstart := p.Position
		open := p.read()
		d := &Node{Kind: "dimension", Open: open}
		if p.peek().Text != "]" {
			d.Expr = p.expression()
		}
		d.Close = p.take("]")
		n.Dimensions = append(n.Dimensions, p.mark(d, dstart))
	}
	if p.Err == nil && p.peek().Text == "=" {
		n.Op = p.read()
		n.Init = p.initializer()
	}
	if semi {
		n.Semi = p.take(";")
	}
	return p.mark(n, start)
}
func (p *Parser) initializer() *Node {
	if p.peek().Text == "{" {
		return p.list("initializer", "{", "}", true)
	}
	return p.expression()
}
func (p *Parser) block() *Node {
	start := p.Position
	n := &Node{Kind: "block", Open: p.take("{")}
	for p.Err == nil && p.peek().Text != "}" && p.peek().Kind != "end" {
		n.Elements = append(n.Elements, p.statement())
	}
	n.Close = p.take("}")
	return p.mark(n, start)
}
func (p *Parser) statement() *Node {
	start := p.Position
	t := p.peek()
	if t.Text == "{" {
		return p.block()
	}
	if typeName(t) {
		typ, name := p.read(), p.identifier()
		return p.declaration(typ, name, start, true)
	}
	n := &Node{Kind: t.Text, Token: p.read()}
	switch t.Text {
	case "if", "while":
		n.Open = p.take("(")
		n.Expr = p.expression()
		n.Close = p.take(")")
		if p.Err == nil {
			n.Body = p.statement()
		}
		if t.Text == "if" && p.Err == nil && p.peek().Text == "else" {
			n.ElseToken = p.read()
			n.Else = p.statement()
		}
	case "for":
		n.Open = p.take("(")
		if p.Err == nil && p.peek().Text != ";" {
			if typeName(p.peek()) {
				initStart := p.Position
				typ, name := p.read(), p.identifier()
				n.Init = p.declaration(typ, name, initStart, false)
			} else {
				n.Init = p.simple()
			}
		}
		n.Semi = p.take(";")
		if p.Err == nil && p.peek().Text != ";" {
			n.Cond = p.expression()
		}
		n.Semi2 = p.take(";")
		if p.Err == nil && p.peek().Text != ")" {
			n.Update = p.simple()
		}
		n.Close = p.take(")")
		if p.Err == nil {
			n.Body = p.statement()
		}
	case "switch":
		n.Open = p.take("(")
		n.Expr = p.expression()
		n.Close = p.take(")")
		bodyStart := p.Position
		body := &Node{Kind: "switchbody", Open: p.take("{")}
		for p.Err == nil && (p.peek().Text == "case" || p.peek().Text == "default") {
			clauseStart := p.Position
			label := p.read()
			clause := &Node{Kind: "clause", Token: label}
			if label.Text == "case" {
				clause.Expr = p.expression()
			}
			clause.Colon = p.take(":")
			for p.Err == nil && !wordIn("case default }", p.peek().Text) && p.peek().Kind != "end" {
				clause.Elements = append(clause.Elements, p.statement())
			}
			body.Elements = append(body.Elements, p.mark(clause, clauseStart))
		}
		body.Close = p.take("}")
		n.Body = p.mark(body, bodyStart)
	case "return":
		if p.Err == nil && p.peek().Text != ";" {
			n.Expr = p.expression()
		}
		n.Semi = p.take(";")
	case "break", "continue":
		n.Semi = p.take(";")
	default:
		p.Position = start
		n = p.simple()
		n.Semi = p.take(";")
	}
	return p.mark(n, start)
}
func (p *Parser) simple() *Node {
	start := p.Position
	left := p.expression()
	n := &Node{Kind: "simple", Expr: left}
	if p.Err == nil && wordIn("= += -= *= /= %=", p.peek().Text) {
		op := p.read()
		n = &Node{Kind: "assignment", Left: left, Op: op, Right: p.expression()}
	}
	return p.mark(n, start)
}
func (p *Parser) expression() *Node {
	start := p.Position
	n := p.binary(1)
	if p.Err == nil && p.peek().Text == "?" {
		question := p.read()
		then := p.expression()
		colon := p.take(":")
		other := p.expression()
		n = p.mark(&Node{Kind: "conditional", Expr: n, Op: question, Then: then, Colon: colon, Else: other}, start)
	}
	return n
}
func (p *Parser) binary(level int) *Node {
	if level == 7 {
		return p.unary()
	}
	left := p.binary(level + 1)
	for p.Err == nil && precedence(p.peek().Text) == level {
		op := p.read()
		right := p.binary(level + 1)
		left = &Node{Kind: "binary", Left: left, Op: op, Right: right, First: left.First, Last: right.Last}
	}
	return left
}
func (p *Parser) unary() *Node {
	start := p.Position
	if p.Err != nil {
		return &Node{Kind: "atom", Token: p.peek(), First: start, Last: start}
	}
	if p.peek().Text == "-" || p.peek().Text == "!" {
		op := p.read()
		return p.mark(&Node{Kind: "unary", Op: op, Expr: p.unary()}, start)
	}
	t := p.peek()
	var n *Node
	if t.Kind == "identifier" || t.Kind == "number" || t.Kind == "string" || t.Text == "true" || t.Text == "false" {
		n = &Node{Kind: "atom", Token: p.read(), First: start, Last: start}
	} else if t.Text == "(" {
		open := p.read()
		inner := p.expression()
		close := p.take(")")
		n = p.mark(&Node{Kind: "paren", Open: open, Close: close, Expr: inner}, start)
	} else {
		p.fail("expression")
		return &Node{Kind: "atom", Token: t, First: start, Last: start}
	}
	for p.Err == nil {
		switch p.peek().Text {
		case "(":
			args := p.list("arguments", "(", ")", false)
			n = p.mark(&Node{Kind: "call", Left: n, Init: args}, start)
		case "[":
			open := p.read()
			index := p.expression()
			close := p.take("]")
			n = p.mark(&Node{Kind: "index", Left: n, Open: open, Close: close, Expr: index}, start)
		case ".":
			op := p.read()
			name := p.identifier()
			n = p.mark(&Node{Kind: "member", Left: n, Op: op, Name: name}, start)
		default:
			return n
		}
	}
	return n
}
