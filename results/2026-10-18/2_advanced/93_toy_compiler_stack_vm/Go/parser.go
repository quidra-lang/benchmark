package main

type Expr struct {
	Kind, Type string
	Token      Token
	Value      int64
	Children   []*Expr
	Referent   *Symbol
}

func (e *Expr) position() Position { return e.Token.Position }

type Declaration struct {
	Type            string
	Name            Token
	Array, Function bool
	Size            Token
	Initializer     *Expr
	Parameters      []*Declaration
	Body            *Statement
	Symbol          *Symbol
	Slots           []*Symbol
}
type Statement struct {
	Kind                           string
	Token, Close                   Token
	Declaration                    *Declaration
	Expr, Index, Condition         *Expr
	Expressions                    []*Expr
	Statements                     []*Statement
	Then, Else, Body, Init, Update *Statement
	Referent                       *Symbol
}
type Program struct {
	Declarations       []*Declaration
	End                Token
	Globals, Functions []*Declaration
	Names              map[string]*Symbol
	Symbols            []*Symbol
}
type Parser struct {
	Tokens []Token
	Index  int
}

func (p *Parser) peek() Token { return p.Tokens[p.Index] }
func (p *Parser) fail() {
	t := p.peek()
	message := "unexpected '" + t.Spelling + "'"
	if t.Kind == "END" {
		message = "unexpected end of program"
	}
	panic(&CompileError{"syntax", message, t.Position})
}
func (p *Parser) take(kind string) Token {
	if p.peek().Kind != kind {
		p.fail()
	}
	t := p.peek()
	p.Index++
	return t
}
func (p *Parser) accept(kind string) bool {
	if p.peek().Kind != kind {
		return false
	}
	p.Index++
	return true
}
func isType(t Token) bool { return wordIn("int bool void", t.Kind) }
func (p *Parser) declarationStart() *Declaration {
	if !isType(p.peek()) {
		p.fail()
	}
	typ := p.peek().Kind
	p.Index++
	return &Declaration{Type: typ, Name: p.take("identifier")}
}
func (p *Parser) program() *Program {
	out := &Program{}
	for p.peek().Kind != "END" {
		d := p.declarationStart()
		if p.accept("(") {
			d.Function = true
			if !p.accept(")") {
				d.Parameters = append(d.Parameters, p.declarationStart())
				for p.accept(",") {
					d.Parameters = append(d.Parameters, p.declarationStart())
				}
				p.take(")")
			}
			d.Body = p.block()
			out.Functions = append(out.Functions, d)
		} else {
			if p.accept("[") {
				d.Array = true
				d.Size = p.take("integer")
				p.take("]")
			} else if p.accept("=") {
				d.Initializer = p.expression(1)
			}
			p.take(";")
			out.Globals = append(out.Globals, d)
		}
		out.Declarations = append(out.Declarations, d)
	}
	out.End = p.peek()
	return out
}
func (p *Parser) block() *Statement {
	s := &Statement{Kind: "block", Token: p.take("{")}
	for p.peek().Kind != "}" {
		if p.peek().Kind == "END" {
			p.fail()
		}
		if isType(p.peek()) {
			start := p.peek()
			d := p.declarationStart()
			if p.accept("=") {
				d.Initializer = p.expression(1)
			}
			p.take(";")
			s.Statements = append(s.Statements, &Statement{Kind: "declaration", Token: start, Declaration: d})
		} else {
			s.Statements = append(s.Statements, p.statement())
		}
	}
	s.Close = p.take("}")
	return s
}
func (p *Parser) statement() *Statement {
	t := p.peek()
	if t.Kind == "{" {
		return p.block()
	}
	p.Index++
	s := &Statement{Kind: t.Kind, Token: t}
	switch t.Kind {
	case "if":
		p.take("(")
		s.Condition = p.expression(1)
		p.take(")")
		s.Then = p.statement()
		if p.accept("else") {
			s.Else = p.statement()
		}
	case "while":
		p.take("(")
		s.Condition = p.expression(1)
		p.take(")")
		s.Body = p.statement()
	case "for":
		p.take("(")
		if isType(p.peek()) {
			start := p.peek()
			d := p.declarationStart()
			p.take("=")
			d.Initializer = p.expression(1)
			s.Init = &Statement{Kind: "declaration", Token: start, Declaration: d}
		} else if p.peek().Kind != ";" {
			s.Init = p.simple()
		}
		p.take(";")
		if p.peek().Kind != ";" {
			s.Condition = p.expression(1)
		}
		p.take(";")
		if p.peek().Kind != ")" {
			s.Update = p.simple()
		}
		p.take(")")
		s.Body = p.statement()
	case "break", "continue":
		p.take(";")
	case "return":
		if p.peek().Kind != ";" {
			s.Expr = p.expression(1)
		}
		p.take(";")
	case "print":
		p.take("(")
		s.Expressions = append(s.Expressions, p.expression(1))
		for p.accept(",") {
			s.Expressions = append(s.Expressions, p.expression(1))
		}
		p.take(")")
		p.take(";")
	case "identifier", "read":
		p.Index--
		s = p.simple()
		p.take(";")
	default:
		p.Index--
		p.fail()
	}
	return s
}
func (p *Parser) call(t Token) *Expr {
	p.take("(")
	arguments := []*Expr{}
	if !p.accept(")") {
		arguments = append(arguments, p.expression(1))
		for p.accept(",") {
			arguments = append(arguments, p.expression(1))
		}
		p.take(")")
	}
	return &Expr{Kind: "call", Token: t, Children: arguments}
}
func (p *Parser) simple() *Statement {
	t := p.peek()
	if t.Kind == "read" {
		p.Index++
		p.take("(")
		p.take(")")
		return &Statement{Kind: "call", Token: t, Expr: &Expr{Kind: "read", Token: t}}
	}
	t = p.take("identifier")
	if p.peek().Kind == "(" {
		return &Statement{Kind: "call", Token: t, Expr: p.call(t)}
	}
	s := &Statement{Kind: "assignment", Token: t}
	if p.accept("[") {
		s.Index = p.expression(1)
		p.take("]")
	}
	p.take("=")
	s.Expr = p.expression(1)
	return s
}
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
func (p *Parser) expression(minimum int) *Expr {
	left := p.unary()
	for {
		level := precedence(p.peek().Kind)
		if level == 0 || level < minimum {
			break
		}
		op := p.peek()
		p.Index++
		right := p.expression(level + 1)
		left = &Expr{Kind: "binary", Token: op, Children: []*Expr{left, right}}
	}
	return left
}
func (p *Parser) unary() *Expr {
	if p.peek().Kind == "-" || p.peek().Kind == "!" {
		op := p.peek()
		p.Index++
		return &Expr{Kind: "unary", Token: op, Children: []*Expr{p.unary()}}
	}
	return p.primary()
}
func (p *Parser) primary() *Expr {
	t := p.peek()
	switch t.Kind {
	case "integer":
		p.Index++
		return &Expr{Kind: "integer", Token: t, Value: t.Integer}
	case "true", "false":
		p.Index++
		value := int64(0)
		if t.Kind == "true" {
			value = 1
		}
		return &Expr{Kind: "boolean", Token: t, Value: value}
	case "read":
		p.Index++
		p.take("(")
		p.take(")")
		return &Expr{Kind: "read", Token: t}
	case "(":
		p.Index++
		e := p.expression(1)
		p.take(")")
		return e
	case "identifier":
		p.Index++
		if p.peek().Kind == "(" {
			return p.call(t)
		}
		if p.accept("[") {
			index := p.expression(1)
			p.take("]")
			return &Expr{Kind: "array", Token: t, Children: []*Expr{index}}
		}
		return &Expr{Kind: "variable", Token: t}
	}
	p.fail()
	return nil
}
func parse(tokens []Token) (program *Program, err *CompileError) {
	defer func() {
		if value := recover(); value != nil {
			if failure, ok := value.(*CompileError); ok {
				err = failure
			} else {
				panic(value)
			}
		}
	}()
	p := Parser{Tokens: tokens}
	program = p.program()
	return
}
