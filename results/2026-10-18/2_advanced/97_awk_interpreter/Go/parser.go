package main

type Binding struct {
	Function *Item
	Name     string
}
type Expr struct {
	Kind, Name, Op     string
	Position           Position
	Value              Value
	Left, Right, Third *Expr
	Args               []*Expr
	Binding            Binding
	Function           *Item
	Prefix             bool
}
type Statement struct {
	Kind             string
	Position         Position
	Exprs            []*Expr
	Body, Else       *Statement
	Statements       []*Statement
	Variable, Array  *Expr
	Redirect         *Expr
	RedirectMode     string
	RedirectPosition Position
	WholeDelete      bool
}
type Item struct {
	Kind, Name, Flavor          string
	Position, NamePosition      Position
	Parameters                  []*Expr
	ParameterNames              map[string]bool
	Body                        *Statement
	Patterns                    []*Expr
	Count, Calls, Active, Depth int
	Inside                      bool
}
type Parser struct {
	Tokens       []Token
	Index, Loops int
	Function     bool
	Phase        string
}

func (p *Parser) peek() Token { return p.Tokens[p.Index] }
func (p *Parser) take() Token {
	token := p.peek()
	p.Index++
	return token
}
func (p *Parser) fail() { panic(SyntaxIssue{p.peek().Position}) }
func (p *Parser) accept(spelling string) bool {
	if p.peek().Spelling != spelling {
		return false
	}
	p.Index++
	return true
}
func (p *Parser) expect(spelling string) Token {
	if p.peek().Spelling != spelling {
		p.fail()
	}
	return p.take()
}
func (p *Parser) newlines() {
	for p.accept("\n") {
	}
}
func (p *Parser) name() *Expr {
	if p.peek().Kind != "name" {
		p.fail()
	}
	token := p.take()
	return &Expr{Kind: "name", Name: token.Spelling, Position: token.Position}
}
func lvalue(e *Expr) bool { return e.Kind == "name" || e.Kind == "array" || e.Kind == "field" }
func (p *Parser) parse() []*Item {
	items := []*Item{}
	for p.peek().Kind != "end" {
		if p.accept("\n") || p.accept(";") {
			continue
		}
		start := p.peek()
		if p.accept("function") {
			if p.peek().Kind != "name" && p.peek().Kind != "function_name" {
				p.fail()
			}
			name := p.take()
			p.expect("(")
			parameters := []*Expr{}
			if p.peek().Spelling != ")" {
				for {
					parameter := p.name()
					parameter.Kind = "parameter"
					parameters = append(parameters, parameter)
					if !p.accept(",") {
						break
					}
					p.newlines()
				}
			}
			p.expect(")")
			p.newlines()
			p.Function = true
			body := p.block()
			p.Function = false
			items = append(items, &Item{Kind: "function", Name: name.Spelling, NamePosition: name.Position, Position: start.Position, Parameters: parameters, Body: body})
			continue
		}
		flavor := ""
		patterns := []*Expr{}
		if start.Spelling == "BEGIN" || start.Spelling == "END" {
			flavor = p.take().Spelling
		} else if start.Spelling == "{" {
			flavor = "all"
		} else {
			patterns = append(patterns, p.expression(true))
			if p.accept(",") {
				p.newlines()
				patterns = append(patterns, p.expression(true))
			}
			flavor = "pattern"
			if len(patterns) == 2 {
				flavor = "range"
			}
		}
		p.Phase = flavor
		var body *Statement
		if flavor == "BEGIN" || flavor == "END" || flavor == "all" || p.peek().Spelling == "{" {
			body = p.block()
		} else if p.peek().Spelling != "\n" && p.peek().Spelling != ";" && p.peek().Kind != "end" {
			p.fail()
		}
		p.Phase = ""
		items = append(items, &Item{Kind: "rule", Flavor: flavor, Position: start.Position, Patterns: patterns, Body: body})
	}
	return items
}
func (p *Parser) block() *Statement {
	opening := p.expect("{")
	out := &Statement{Kind: "block", Position: opening.Position}
	for p.peek().Spelling != "}" {
		if p.accept("\n") || p.accept(";") {
			continue
		}
		out.Statements = append(out.Statements, p.statement())
	}
	p.expect("}")
	return out
}
func (p *Parser) condition() *Expr {
	p.expect("(")
	value := p.expression(true)
	p.expect(")")
	return value
}
func (p *Parser) loopBody() *Statement {
	p.newlines()
	p.Loops++
	body := p.statement()
	p.Loops--
	return body
}
func (p *Parser) terminator() {
	if p.accept(";") || p.accept("\n") {
		return
	}
	if p.peek().Spelling != "}" {
		p.fail()
	}
}
func (p *Parser) statement() *Statement {
	token := p.peek()
	kind := token.Spelling
	if kind == "{" {
		return p.block()
	}
	if p.accept(";") {
		return &Statement{Kind: "empty", Position: token.Position}
	}
	out := &Statement{Kind: kind, Position: token.Position}
	switch kind {
	case "if":
		p.take()
		out.Exprs = []*Expr{p.condition()}
		p.newlines()
		out.Body = p.statement()
		p.newlines()
		if p.accept("else") {
			p.newlines()
			out.Else = p.statement()
		}
		return out
	case "while":
		p.take()
		out.Exprs = []*Expr{p.condition()}
		out.Body = p.loopBody()
		return out
	case "do":
		p.take()
		out.Body = p.loopBody()
		p.newlines()
		p.expect("while")
		out.Exprs = []*Expr{p.condition()}
		p.terminator()
		return out
	case "for":
		p.take()
		p.expect("(")
		if p.Index+3 < len(p.Tokens) && p.Tokens[p.Index].Kind == "name" && p.Tokens[p.Index+1].Spelling == "in" && p.Tokens[p.Index+2].Kind == "name" && p.Tokens[p.Index+3].Spelling == ")" {
			out.Kind = "for_in"
			out.Variable = p.name()
			p.expect("in")
			out.Array = p.name()
			p.expect(")")
			out.Body = p.loopBody()
			return out
		}
		out.Exprs = make([]*Expr, 3)
		if p.peek().Spelling != ";" {
			out.Exprs[0] = p.expression(true)
		}
		p.expect(";")
		p.newlines()
		if p.peek().Spelling != ";" {
			out.Exprs[1] = p.expression(true)
		}
		p.expect(";")
		p.newlines()
		if p.peek().Spelling != ")" {
			out.Exprs[2] = p.expression(true)
		}
		p.expect(")")
		out.Body = p.loopBody()
		return out
	case "print", "printf":
		p.take()
		p.output(out)
	case "delete":
		p.take()
		out.Array = p.name()
		out.WholeDelete = true
		if p.accept("[") {
			out.WholeDelete = false
			out.Exprs = p.expressionList(true)
			p.expect("]")
		}
	case "next", "break", "continue", "exit", "return":
		p.take()
		if kind == "next" && !p.Function && (p.Phase == "BEGIN" || p.Phase == "END") || kind == "return" && !p.Function || (kind == "break" || kind == "continue") && p.Loops == 0 {
			panic(SyntaxIssue{token.Position})
		}
		if (kind == "exit" || kind == "return") && !wordIn("; }", p.peek().Spelling) && p.peek().Spelling != "\n" {
			out.Exprs = []*Expr{p.expression(true)}
		}
	default:
		out.Kind = "expression"
		out.Exprs = []*Expr{p.expression(true)}
	}
	p.terminator()
	return out
}
func (p *Parser) parenthesizedOutput() bool {
	if p.peek().Spelling != "(" {
		return false
	}
	depth := 0
	for i := p.Index; i < len(p.Tokens); i++ {
		switch p.Tokens[i].Spelling {
		case "(":
			depth++
		case ")":
			depth--
			if depth == 0 {
				if i+1 == len(p.Tokens) {
					return false
				}
				next := p.Tokens[i+1]
				return next.Kind == "end" || next.Spelling == "\n" || wordIn("; } > >>", next.Spelling)
			}
		}
	}
	return false
}
func (p *Parser) output(out *Statement) {
	if p.parenthesizedOutput() {
		p.expect("(")
		out.Exprs = p.expressionList(true)
		p.expect(")")
	} else if p.peek().Spelling != "\n" && !wordIn("; } > >>", p.peek().Spelling) {
		out.Exprs = p.expressionList(false)
	}
	if out.Kind == "printf" && len(out.Exprs) == 0 {
		p.fail()
	}
	if p.peek().Spelling == ">" || p.peek().Spelling == ">>" {
		redirect := p.take()
		out.RedirectMode = redirect.Spelling
		out.RedirectPosition = redirect.Position
		out.Redirect = p.concatenation()
	}
}
func (p *Parser) expressionList(greater bool) []*Expr {
	out := []*Expr{p.expression(greater)}
	for p.accept(",") {
		p.newlines()
		out = append(out, p.expression(greater))
	}
	return out
}
func (p *Parser) expression(greater bool) *Expr {
	left := p.conditional(greater)
	if lvalue(left) && wordIn("= += -= *= /= %= ^=", p.peek().Spelling) {
		op := p.take()
		return &Expr{Kind: "assignment", Op: op.Spelling, Position: op.Position, Left: left, Right: p.expression(greater)}
	}
	return left
}
func (p *Parser) conditional(greater bool) *Expr {
	condition := p.logical(0, greater)
	if !p.accept("?") {
		return condition
	}
	position := p.Tokens[p.Index-1].Position
	first := p.conditional(greater)
	p.expect(":")
	second := p.conditional(greater)
	return &Expr{Kind: "conditional", Position: position, Left: condition, Right: first, Third: second}
}
func binary(op Token, left, right *Expr) *Expr {
	return &Expr{Kind: "binary", Op: op.Spelling, Position: op.Position, Left: left, Right: right}
}
func (p *Parser) logical(level int, greater bool) *Expr {
	if level == 2 {
		return p.membership(greater)
	}
	op := "||"
	if level == 1 {
		op = "&&"
	}
	left := p.logical(level+1, greater)
	for p.peek().Spelling == op {
		token := p.take()
		p.newlines()
		left = binary(token, left, p.logical(level+1, greater))
	}
	return left
}
func (p *Parser) membership(greater bool) *Expr {
	left := p.comparison(greater)
	for p.peek().Spelling == "in" {
		token := p.take()
		array := p.name()
		left = &Expr{Kind: "membership", Position: token.Position, Args: []*Expr{left}, Right: array}
	}
	return left
}
func (p *Parser) comparison(greater bool) *Expr {
	left := p.concatenation()
	for wordIn("< <= == != >= >", p.peek().Spelling) && (greater || p.peek().Spelling != ">") {
		op := p.take()
		left = binary(op, left, p.concatenation())
	}
	return left
}
func (p *Parser) concatenation() *Expr {
	left := p.additive()
	for wordIn("number string name function_name builtin", p.peek().Kind) || wordIn("$ ( ++ --", p.peek().Spelling) {
		op := Token{Spelling: "concat", Position: p.peek().Position}
		left = binary(op, left, p.additive())
	}
	return left
}
func (p *Parser) additive() *Expr {
	left := p.multiplicative()
	for p.peek().Spelling == "+" || p.peek().Spelling == "-" {
		op := p.take()
		left = binary(op, left, p.multiplicative())
	}
	return left
}
func (p *Parser) multiplicative() *Expr {
	left := p.unary()
	for wordIn("* / %", p.peek().Spelling) {
		op := p.take()
		left = binary(op, left, p.unary())
	}
	return left
}
func (p *Parser) unary() *Expr {
	if wordIn("! - +", p.peek().Spelling) {
		op := p.take()
		return &Expr{Kind: "unary", Position: op.Position, Op: op.Spelling, Left: p.unary()}
	}
	left := p.postfix()
	if p.peek().Spelling == "^" {
		op := p.take()
		left = binary(op, left, p.unary())
	}
	return left
}
func (p *Parser) prefix() *Expr {
	op := p.take()
	return &Expr{Kind: "increment", Position: op.Position, Op: op.Spelling, Prefix: true, Left: p.location()}
}
func (p *Parser) postfix() *Expr {
	if p.peek().Spelling == "++" || p.peek().Spelling == "--" {
		return p.prefix()
	}
	left := p.atom()
	if lvalue(left) && (p.peek().Spelling == "++" || p.peek().Spelling == "--") {
		op := p.take()
		return &Expr{Kind: "increment", Position: op.Position, Op: op.Spelling, Left: left}
	}
	return left
}
func (p *Parser) location() *Expr {
	if p.peek().Kind == "name" {
		name := p.name()
		if p.accept("[") {
			name.Kind = "array"
			name.Args = p.expressionList(true)
			p.expect("]")
		}
		return name
	}
	if p.accept("$") {
		position := p.Tokens[p.Index-1].Position
		var index *Expr
		if p.peek().Spelling == "++" || p.peek().Spelling == "--" {
			index = p.prefix()
		} else {
			index = p.atom()
		}
		return &Expr{Kind: "field", Position: position, Left: index}
	}
	p.fail()
	return nil
}
func (p *Parser) atom() *Expr {
	token := p.peek()
	if token.Kind == "number" || token.Kind == "string" {
		p.take()
		value := numeric(token.Number)
		if token.Kind == "string" {
			value = stringValue(token.Text)
		}
		return &Expr{Kind: token.Kind, Position: token.Position, Value: value}
	}
	if token.Kind == "name" || token.Spelling == "$" {
		return p.location()
	}
	if p.accept("(") {
		expressions := p.expressionList(true)
		p.expect(")")
		if len(expressions) == 1 {
			return &Expr{Kind: "paren", Position: token.Position, Left: expressions[0]}
		}
		p.expect("in")
		return &Expr{Kind: "membership", Position: token.Position, Args: expressions, Right: p.name()}
	}
	if token.Kind == "function_name" || token.Kind == "builtin" {
		p.take()
		arguments := []*Expr{}
		if p.accept("(") {
			if p.peek().Spelling != ")" {
				arguments = p.expressionList(true)
			}
			p.expect(")")
		} else if token.Kind == "function_name" || token.Spelling != "length" {
			p.fail()
		}
		kind := "call"
		if token.Kind == "builtin" {
			kind = "builtin"
			count := len(arguments)
			valid := count == 1
			switch token.Spelling {
			case "length":
				valid = count <= 1
			case "substr", "split":
				valid = count == 2 || count == 3
			case "index":
				valid = count == 2
			case "sprintf":
				valid = count >= 1
			}
			if !valid || token.Spelling == "split" && arguments[1].Kind != "name" {
				panic(SyntaxIssue{token.Position})
			}
		}
		return &Expr{Kind: kind, Position: token.Position, Name: token.Spelling, Args: arguments}
	}
	if p.accept("getline") {
		out := &Expr{Kind: "getline", Position: token.Position}
		if p.peek().Kind == "name" || p.peek().Spelling == "$" {
			out.Left = p.location()
		}
		if p.accept("<") {
			out.Right = p.atom()
		}
		return out
	}
	p.fail()
	return nil
}
