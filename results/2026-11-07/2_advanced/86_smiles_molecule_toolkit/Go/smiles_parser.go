package main

import "strings"

func digit(c byte) bool { return c >= '0' && c <= '9' }
func organic(source string, at int) (*Atom, int, bool) {
	if at+1 < len(source) && (source[at:at+2] == "Cl" || source[at:at+2] == "Br") {
		return &Atom{Symbol: source[at : at+2]}, at + 2, true
	}
	c := source[at]
	if strings.ContainsRune("BCNOPSFI", rune(c)) {
		return &Atom{Symbol: string(c)}, at + 1, true
	}
	if strings.ContainsRune("bcnops", rune(c)) {
		return &Atom{Symbol: strings.ToUpper(string(c)), Aromatic: true}, at + 1, true
	}
	return nil, at, false
}
func bracket(content string, elements map[string]Element) (*Atom, string) {
	a := &Atom{Bracket: true}
	i := 0
	for i < len(content) && digit(content[i]) {
		i++
	}
	if i >= 4 || (i > 0 && content[0] == '0') {
		return nil, "bad bracket atom"
	}
	if i > 0 {
		a.Mass = integer(content[:i])
	}
	if i == len(content) {
		return nil, "bad bracket atom"
	}
	c := content[i]
	if strings.ContainsRune("bcnops", rune(c)) {
		a.Symbol = strings.ToUpper(string(c))
		a.Aromatic = true
		i++
	} else if c >= 'A' && c <= 'Z' {
		if i+1 < len(content) && content[i+1] >= 'a' && content[i+1] <= 'z' {
			if _, ok := elements[content[i:i+2]]; ok {
				a.Symbol = content[i : i+2]
				i += 2
			}
		}
		if a.Symbol == "" {
			symbol := string(c)
			if _, ok := elements[symbol]; !ok {
				return nil, "unknown element"
			}
			a.Symbol = symbol
			i++
		}
	} else {
		return nil, "bad bracket atom"
	}
	if strings.HasPrefix(content[i:], "@@") {
		i += 2
	} else if i < len(content) && content[i] == '@' {
		i++
	}
	if i < len(content) && content[i] == 'H' {
		a.Hydrogens = 1
		i++
		if i < len(content) && digit(content[i]) {
			a.Hydrogens = int(content[i] - '0')
			i++
		}
	}
	if i < len(content) && (content[i] == '+' || content[i] == '-') {
		sign := 1
		if content[i] == '-' {
			sign = -1
		}
		i++
		magnitude := 1
		if i < len(content) && content[i] >= '1' && content[i] <= '9' {
			magnitude = int(content[i] - '0')
			i++
		}
		a.Charge = sign * magnitude
	}
	if i != len(content) {
		return nil, "bad bracket atom"
	}
	return a, ""
}
func symbolType(c byte) int {
	switch c {
	case '-', '/', '\\':
		return 1
	case '=':
		return 2
	case '#':
		return 3
	case ':':
		return 4
	case '~':
		return 5
	}
	return 0
}
func bondSymbol(c byte, pattern bool) bool {
	if pattern {
		return strings.ContainsRune("-=#:~", rune(c))
	}
	return strings.ContainsRune("-/\\=#:", rune(c))
}

type Branch struct{ Atom, Column int }
type OpenRing struct {
	Atom, Column int
	Symbol       byte
}

func parseSMILES(source string, elements map[string]Element, pattern bool) (*Molecule, *ParseError) {
	m := &Molecule{}
	current := -1
	pending := byte(0)
	pendingColumn := 0
	stack := []Branch{}
	open := map[int]OpenRing{}
	existing := map[[2]int]bool{}
	fail := func(reason string, column int) (*Molecule, *ParseError) { return nil, &ParseError{reason, column} }
	addBond := func(a, b int, symbol byte) {
		if a > b {
			a, b = b, a
		}
		bond := &Bond{A: a, B: b, Symbol: symbol}
		if pattern {
			kind := symbolType(symbol)
			if kind == 0 {
				bond.Match = (1 << 1) | (1 << 4)
			} else if kind == 5 {
				bond.Match = (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4)
			} else {
				bond.Match = 1 << kind
			}
		}
		m.Bonds = append(m.Bonds, bond)
		existing[[2]int{a, b}] = true
	}
	for i := 0; i < len(source); {
		c := source[i]
		column := i + 1
		switch {
		case bondSymbol(c, pattern):
			if current < 0 || pending != 0 {
				return fail("misplaced bond", column)
			}
			pending = c
			pendingColumn = column
			i++
		case c == '(':
			if current < 0 || pending != 0 || (i > 0 && source[i-1] == '(') {
				return fail("misplaced branch", column)
			}
			stack = append(stack, Branch{current, column})
			i++
		case c == ')':
			if len(stack) == 0 {
				return fail("unmatched parenthesis", column)
			}
			if pending != 0 {
				return fail("dangling bond", pendingColumn)
			}
			if i > 0 && source[i-1] == '(' {
				return fail("empty branch", column)
			}
			last := stack[len(stack)-1]
			stack = stack[:len(stack)-1]
			current = last.Atom
			i++
		case digit(c) || c == '%':
			if current < 0 {
				return fail("misplaced ring closure", column)
			}
			number := 0
			if c == '%' {
				if i+2 >= len(source) || !digit(source[i+1]) || !digit(source[i+2]) {
					return fail("bad ring number", column)
				}
				number = integer(source[i+1 : i+3])
				i += 3
			} else {
				number = int(c - '0')
				i++
			}
			symbol := pending
			pending = 0
			if old, ok := open[number]; ok {
				if old.Atom == current {
					return fail("self bond", column)
				}
				if old.Symbol != 0 && symbol != 0 {
					same := old.Symbol == symbol
					if !pattern {
						same = symbolType(old.Symbol) == symbolType(symbol)
					}
					if !same {
						return fail("ring bond mismatch", column)
					}
				}
				a, b := old.Atom, current
				if a > b {
					a, b = b, a
				}
				if existing[[2]int{a, b}] {
					return fail("duplicate bond", column)
				}
				if symbol == 0 {
					symbol = old.Symbol
				}
				addBond(old.Atom, current, symbol)
				delete(open, number)
			} else {
				open[number] = OpenRing{current, column, symbol}
			}
		default:
			var atom *Atom
			var next int
			var reason string
			if pattern {
				atom, next, reason = patternAtom(source, i)
			} else if c == '[' {
				end := strings.IndexByte(source[i+1:], ']')
				if end < 0 {
					return fail("unclosed bracket", column)
				}
				end += i + 1
				atom, reason = bracket(source[i+1:end], elements)
				next = end + 1
			} else {
				var ok bool
				atom, next, ok = organic(source, i)
				if !ok {
					reason = "unexpected character"
				}
			}
			if reason != "" {
				return fail(reason, column)
			}
			atom.Column = column
			m.Atoms = append(m.Atoms, atom)
			index := len(m.Atoms) - 1
			if current >= 0 {
				addBond(current, index, pending)
			}
			current = index
			pending = 0
			i = next
		}
	}
	if pending != 0 {
		return fail("dangling bond", pendingColumn)
	}
	if len(stack) > 0 {
		return fail("unmatched parenthesis", stack[0].Column)
	}
	if len(open) > 0 {
		column := len(source) + 1
		for _, r := range open {
			column = min(column, r.Column)
		}
		return fail("unclosed ring", column)
	}
	m.Build()
	return m, nil
}
