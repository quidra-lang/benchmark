package main

type Node struct {
	Kind, Value, Left, Right string
	Column, RightColumn      int
	Items                    []*Node
	Rows                     [][]*Node
	Base, Sub, Sup           *Node
}

func emptyRow() *Node { return &Node{Kind: "row"} }
func collapse(nodes []*Node) *Node {
	if len(nodes) == 1 {
		return nodes[0]
	}
	return &Node{Kind: "row", Items: nodes}
}
func checkBraces(tokens []Token) *Issue {
	stack := []int{}
	for _, t := range tokens {
		if t.Kind == "{" {
			stack = append(stack, t.Column)
		} else if t.Kind == "}" {
			if len(stack) == 0 {
				return &Issue{t.Column, "unmatched }"}
			}
			stack = stack[:len(stack)-1]
		}
	}
	if len(stack) > 0 {
		return &Issue{stack[len(stack)-1], "unclosed {"}
	}
	return nil
}

type Parser struct {
	Tokens        []Token
	Position, End int
	Err           *Issue
	Tag, Label    *Token
}

func (p *Parser) peek() Token {
	if p.Position == len(p.Tokens) {
		return Token{"eof", "", p.End}
	}
	return p.Tokens[p.Position]
}
func (p *Parser) read() Token {
	t := p.peek()
	if p.Position < len(p.Tokens) {
		p.Position++
	}
	return t
}
func (p *Parser) fail(column int, message string) {
	if p.Err == nil {
		p.Err = &Issue{column, message}
	}
}
func terminator(t Token) bool { return containsWord("} & newline right end eof", t.Kind) }
func (p *Parser) unexpected(t Token) {
	message := map[string]string{"right": `unexpected \right`, "end": `unexpected \end`, "&": "misplaced &", "newline": `misplaced \\`}[t.Kind]
	p.fail(t.Column, message)
}
func (p *Parser) elements(top, index bool) []*Node {
	out := []*Node{}
	for p.Err == nil {
		t := p.peek()
		if terminator(t) || index && t.Kind == "symbol" && t.Value == "]" {
			break
		}
		if t.Kind == "tag" || t.Kind == "label" {
			if !top {
				p.fail(t.Column, "misplaced \\"+t.Kind)
				break
			}
			target := &p.Tag
			if t.Kind == "label" {
				target = &p.Label
			}
			if *target != nil {
				p.fail(t.Column, "duplicate \\"+t.Kind)
				break
			}
			p.read()
			copy := t
			*target = &copy
			continue
		}
		out = append(out, p.element())
	}
	return out
}
func (p *Parser) element() *Node {
	base := emptyRow()
	t := p.peek()
	if t.Kind != "^" && t.Kind != "_" {
		base = p.nucleus()
	}
	var sub, sup *Node
	for p.Err == nil && (p.peek().Kind == "^" || p.peek().Kind == "_") {
		t = p.read()
		if t.Kind == "^" {
			if sup != nil {
				p.fail(t.Column, "double superscript")
				break
			}
			sup = p.argument("^")
		} else {
			if sub != nil {
				p.fail(t.Column, "double subscript")
				break
			}
			sub = p.argument("_")
		}
	}
	if sub == nil && sup == nil {
		return base
	}
	return &Node{Kind: "script", Base: base, Sub: sub, Sup: sup}
}
func (p *Parser) argument(name string) *Node {
	if p.Err != nil {
		return emptyRow()
	}
	t := p.peek()
	if !containsWord("identifier number symbol command text eqref { frac binom overset underset sqrt accent", t.Kind) {
		p.fail(t.Column, "missing argument for "+name)
		return emptyRow()
	}
	return p.nucleus()
}
func (p *Parser) delimiter() string {
	t := p.read()
	if t.Kind == "symbol" && containsWord("( ) [ ] | .", t.Value) || t.Kind == "command" && (t.Value == `\{` || t.Value == `\}`) {
		return t.Value
	}
	p.fail(t.Column, "invalid delimiter")
	return "."
}
func (p *Parser) nucleus() *Node {
	if p.Err != nil {
		return emptyRow()
	}
	t := p.read()
	n := &Node{Kind: t.Kind, Value: t.Value, Column: t.Column}
	switch t.Kind {
	case "identifier", "number", "symbol", "command", "text":
		return n
	case "eqref":
		n.Kind = "reference"
		return n
	case "{":
		nodes := p.elements(false, false)
		if p.Err == nil {
			if p.peek().Kind == "}" {
				p.read()
			} else {
				p.unexpected(p.peek())
			}
		}
		return collapse(nodes)
	case "frac", "binom", "overset", "underset":
		first := p.argument("\\" + t.Kind)
		second := p.argument("\\" + t.Kind)
		n.Items = []*Node{first, second}
		return n
	case "sqrt":
		var index *Node
		if p.peek().Kind == "symbol" && p.peek().Value == "[" {
			open := p.read()
			nodes := p.elements(false, true)
			if p.Err == nil {
				if p.peek().Kind != "symbol" || p.peek().Value != "]" {
					p.fail(open.Column, "missing ]")
				} else {
					p.read()
				}
			}
			index = collapse(nodes)
		}
		body := p.argument(`\sqrt`)
		if index != nil {
			n.Kind = "root"
			n.Items = []*Node{index, body}
		} else {
			n.Items = []*Node{body}
		}
		return n
	case "accent":
		n.Items = []*Node{p.argument("\\" + t.Value)}
		return n
	case "left":
		n.Kind = "delim"
		n.Left = p.delimiter()
		body := p.elements(false, false)
		if p.Err == nil {
			if p.peek().Kind != "right" {
				p.fail(t.Column, `missing \right`)
			} else {
				right := p.read()
				n.RightColumn = right.Column
				n.Right = p.delimiter()
			}
		}
		n.Items = []*Node{collapse(body)}
		return n
	case "begin":
		n.Kind = "matrix"
		rows := [][]*Node{{}}
		for p.Err == nil {
			cells := p.elements(false, false)
			rows[len(rows)-1] = append(rows[len(rows)-1], collapse(cells))
			if p.Err != nil {
				break
			}
			end := p.read()
			if end.Kind == "&" {
				continue
			}
			if end.Kind == "newline" {
				rows = append(rows, []*Node{})
				continue
			}
			if end.Kind == "end" {
				if end.Value != t.Value {
					p.fail(end.Column, `mismatched \end`)
				}
				break
			}
			p.fail(t.Column, `missing \end`)
		}
		if len(rows) > 1 {
			last := rows[len(rows)-1]
			if len(last) == 1 && last[0].Kind == "row" && len(last[0].Items) == 0 {
				rows = rows[:len(rows)-1]
			}
		}
		width := 0
		for _, r := range rows {
			width = max(width, len(r))
		}
		for i := range rows {
			for len(rows[i]) < width {
				rows[i] = append(rows[i], emptyRow())
			}
		}
		n.Rows = rows
		return n
	}
	return n
}
