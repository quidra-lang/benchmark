package main

import (
	"fmt"
	"strconv"
	"strings"
)

type Expander struct {
	Macros        map[string]*Macro
	Diagnostic    func(Position, string, string)
	Counter       int
	BuiltinCounts map[string]int
}

func union(a, b map[string]bool) map[string]bool {
	out := map[string]bool{}
	for name := range a {
		out[name] = true
	}
	for name := range b {
		out[name] = true
	}
	return out
}
func intersection(a, b map[string]bool) map[string]bool {
	out := map[string]bool{}
	for name := range a {
		if b[name] {
			out[name] = true
		}
	}
	return out
}
func (e *Expander) error(context *Inclusion, t Token, message string) {
	e.Diagnostic(context.position(t.Line), "error", message)
}
func (e *Expander) builtin(t Token, context *Inclusion) Token {
	e.BuiltinCounts[t.Spelling]++
	kind, spelling := "number", ""
	switch t.Spelling {
	case "__FILE__":
		kind = "string"
		spelling = `"` + context.DisplayFile + `"`
	case "__LINE__":
		spelling = strconv.Itoa(context.position(t.Line).Line)
	case "__COUNTER__":
		spelling = strconv.Itoa(e.Counter)
		e.Counter++
	}
	return Token{Kind: kind, Spelling: spelling, Line: t.Line, Space: t.Space}
}
func (e *Expander) collect(pending []Token, m *Macro, t Token, context *Inclusion) (map[string][]Token, int, Token, bool) {
	arguments := [][]Token{{}}
	separators := []Token{}
	nesting, consumed := 0, 0
	var closing Token
	for index := 1; index < len(pending); index++ {
		current := pending[index]
		if current.Spelling == ")" && nesting == 0 {
			closing = current
			consumed = index + 1
			break
		}
		if current.Spelling == "," && nesting == 0 {
			separators = append(separators, current)
			arguments = append(arguments, []Token{})
		} else {
			if current.Spelling == "(" {
				nesting++
			} else if current.Spelling == ")" {
				nesting--
			}
			arguments[len(arguments)-1] = append(arguments[len(arguments)-1], current)
		}
	}
	if consumed == 0 {
		e.error(context, t, `unterminated argument list invoking macro "`+m.Name+`"`)
		return nil, 0, Token{}, false
	}
	count, fixed := len(arguments), len(m.Parameters)
	if m.Variadic {
		fixed--
	}
	message := ""
	switch {
	case !m.Variadic && fixed == 0 && (count != 1 || len(arguments[0]) > 0):
		message = fmt.Sprintf("macro %q passed %d arguments, but takes just 0", m.Name, count)
	case count < fixed:
		message = fmt.Sprintf("macro %q requires %d arguments, but only %d given", m.Name, fixed, count)
	case count > fixed && !m.Variadic:
		message = fmt.Sprintf("macro %q passed %d arguments, but takes just %d", m.Name, count, fixed)
	}
	if message != "" {
		e.error(context, t, message)
		return nil, 0, Token{}, false
	}
	raw := map[string][]Token{}
	for i := 0; i < fixed; i++ {
		raw[m.Parameters[i]] = copyTokens(arguments[i])
	}
	if m.Variadic {
		variable := []Token{}
		for i := fixed; i < count; i++ {
			if i > fixed {
				variable = append(variable, separators[i-1])
			}
			variable = append(variable, arguments[i]...)
		}
		raw[variadicName] = variable
	}
	return raw, consumed, closing, true
}
func stringize(tokens []Token, sharp Token) Token {
	var value strings.Builder
	value.WriteByte('"')
	for i, t := range tokens {
		if i > 0 && t.Space {
			value.WriteByte(' ')
		}
		spelling := t.Spelling
		if t.Kind == "string" || t.Kind == "character" {
			spelling = strings.ReplaceAll(spelling, `\`, `\\`)
			spelling = strings.ReplaceAll(spelling, `"`, `\"`)
		}
		value.WriteString(spelling)
	}
	value.WriteByte('"')
	return Token{Kind: "string", Spelling: value.String(), Line: sharp.Line, Space: sharp.Space}
}
func (e *Expander) paste(left, right, t Token, context *Inclusion) []Token {
	if left.Kind == "placemarker" {
		right.Space = left.Space
		return []Token{right}
	}
	if right.Kind == "placemarker" {
		return []Token{left}
	}
	spelling := left.Spelling + right.Spelling
	if kind, ok := singleToken(spelling); ok {
		return []Token{{Kind: kind, Spelling: spelling, Line: left.Line, Space: left.Space, Hide: intersection(left.Hide, right.Hide)}}
	}
	e.error(context, t, `pasting "`+left.Spelling+`" and "`+right.Spelling+`" does not give a valid preprocessing token`)
	right.Space = false
	return []Token{left, right}
}

type SubstitutionItem struct {
	Tokens   []Token
	Paste    bool
	Operator Token
}

func (e *Expander) substitute(m *Macro, raw map[string][]Token, t Token, hide map[string]bool, context *Inclusion) []Token {
	replacement := m.Replacement
	items := []SubstitutionItem{}
	expanded := map[string][]Token{}
	for index := 0; index < len(replacement); {
		current := replacement[index]
		if current.Spelling == "#" && m.Function {
			parameter := replacement[index+1].Spelling
			items = append(items, SubstitutionItem{Tokens: []Token{stringize(raw[parameter], current)}})
			index += 2
			continue
		}
		if current.Spelling == "##" {
			items = append(items, SubstitutionItem{Paste: true, Operator: current})
		} else if sequence, parameter := raw[current.Spelling]; current.Kind == "identifier" && parameter {
			adjacent := index > 0 && replacement[index-1].Spelling == "##" || index+1 < len(replacement) && replacement[index+1].Spelling == "##"
			if !adjacent {
				cached, done := expanded[current.Spelling]
				if !done {
					cached = e.expand(sequence, context)
					expanded[current.Spelling] = cached
				}
				sequence = cached
			}
			sequence = copyTokens(sequence)
			if len(sequence) > 0 {
				sequence[0].Space = current.Space
			} else {
				sequence = []Token{{Kind: "placemarker", Line: current.Line, Space: current.Space}}
			}
			items = append(items, SubstitutionItem{Tokens: sequence})
		} else {
			items = append(items, SubstitutionItem{Tokens: []Token{current}})
		}
		index++
	}
	pasted := []Token{}
	for index := 0; index < len(items); {
		item := items[index]
		if !item.Paste {
			pasted = append(pasted, item.Tokens...)
			index++
			continue
		}
		left := pasted[len(pasted)-1]
		pasted = pasted[:len(pasted)-1]
		right := items[index+1].Tokens
		if items[index+1].Paste {
			right = []Token{items[index+1].Operator}
		}
		pasted = append(pasted, e.paste(left, right[0], t, context)...)
		pasted = append(pasted, right[1:]...)
		index += 2
	}
	result := []Token{}
	carry := false
	for _, current := range pasted {
		if current.Kind == "placemarker" {
			carry = carry || current.Space
			continue
		}
		current.Line = t.Line
		current.Space = current.Space || carry
		carry = false
		current.Hide = union(current.Hide, hide)
		result = append(result, current)
	}
	if len(result) > 0 {
		result[0].Space = t.Space
	}
	return result
}
func (e *Expander) expand(sequence []Token, context *Inclusion) []Token {
	pending := copyTokens(sequence)
	result := []Token{}
	for len(pending) > 0 {
		t := pending[0]
		pending = pending[1:]
		if t.Kind != "identifier" || t.Hide[t.Spelling] {
			result = append(result, t)
			continue
		}
		if builtins[t.Spelling] {
			result = append(result, e.builtin(t, context))
			continue
		}
		m := e.Macros[t.Spelling]
		if m == nil || m.Function && (len(pending) == 0 || pending[0].Spelling != "(") {
			result = append(result, t)
			continue
		}
		raw := map[string][]Token{}
		hide := union(t.Hide, map[string]bool{m.Name: true})
		if m.Function {
			collected, consumed, closing, ok := e.collect(pending, m, t, context)
			if !ok {
				result = append(result, t)
				continue
			}
			raw = collected
			pending = pending[consumed:]
			hide = union(intersection(t.Hide, closing.Hide), map[string]bool{m.Name: true})
		}
		replacement := e.substitute(m, raw, t, hide, context)
		m.Expanded++
		if len(replacement) == 0 && t.Space && len(pending) > 0 {
			pending[0].Space = true
		}
		pending = append(replacement, pending...)
	}
	return result
}
