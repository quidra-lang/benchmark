package main

import (
	"fmt"
	"strings"
)

type Position struct{ Line, Column int }
type Token struct {
	Kind, Name, Spelling, Message string
	Integer                       int64
	Position                      Position
	Whitespace                    bool
}

func lower(c byte) bool        { return c >= 'a' && c <= 'z' }
func upper(c byte) bool        { return c >= 'A' && c <= 'Z' }
func digit(c byte) bool        { return c >= '0' && c <= '9' }
func alphanumeric(c byte) bool { return lower(c) || upper(c) || digit(c) || c == '_' }
func symbol(c byte) bool       { return strings.ContainsRune("+-*/\\^<>=~:.?@#&$", rune(c)) }
func lex(source string, startColumn int) []Token {
	tokens := []Token{}
	i, line, column := 0, 1, startColumn
	space := true
	for i < len(source) {
		c := source[i]
		if c == ' ' || c == '\n' {
			space = true
			i++
			if c == '\n' {
				line++
				column = 1
			} else {
				column++
			}
			continue
		}
		if c == '%' {
			space = true
			for i < len(source) && source[i] != '\n' {
				i++
				column++
			}
			continue
		}
		start := i
		t := Token{Position: Position{line, column}, Whitespace: space}
		space = false
		switch {
		case digit(c):
			t.Kind = "integer"
			n := int64(0)
			tooLarge := false
			for i < len(source) && digit(source[i]) {
				if n > 214748364 || n == 214748364 && source[i] > '7' {
					tooLarge = true
				}
				if !tooLarge {
					n = n*10 + int64(source[i]-'0')
				}
				i++
				column++
			}
			t.Integer = n
			if tooLarge {
				t.Kind = "invalid"
				t.Message = "integer too large"
			}
		case lower(c) || upper(c) || c == '_':
			t.Kind = "name"
			if !lower(c) {
				t.Kind = "variable"
			}
			for i < len(source) && alphanumeric(source[i]) {
				i++
				column++
			}
			t.Name = source[start:i]
		case symbol(c):
			for i < len(source) && symbol(source[i]) {
				i++
				column++
			}
			t.Name = source[start:i]
			t.Kind = "name"
			if t.Name == "." && (i == len(source) || source[i] == ' ' || source[i] == '\n' || source[i] == '%') {
				t.Kind = "end"
			}
		case c == '!' || c == ';':
			t.Kind = "name"
			t.Name = string(c)
			i++
			column++
		case strings.ContainsRune(",|()[]", rune(c)):
			t.Kind = "punctuation"
			t.Name = string(c)
			i++
			column++
		case c == '\'':
			t.Kind = "quoted"
			i++
			column++
			var name strings.Builder
			incorrect := false
			closed := false
			for i < len(source) && source[i] != '\n' {
				c = source[i]
				if c == '\'' {
					if i+1 < len(source) && source[i+1] == '\'' {
						name.WriteByte('\'')
						i += 2
						column += 2
						continue
					}
					i++
					column++
					closed = true
					break
				}
				if c == '\\' {
					if i+1 == len(source) || source[i+1] == '\n' {
						i++
						column++
						continue
					}
					next := source[i+1]
					switch next {
					case 'n':
						name.WriteByte('\n')
					case 't':
						name.WriteByte('\t')
					case '\\', '\'':
						name.WriteByte(next)
					default:
						incorrect = true
					}
					i += 2
					column += 2
					continue
				}
				name.WriteByte(c)
				i++
				column++
			}
			if !closed {
				t.Kind = "invalid"
				t.Message = "unterminated quoted atom"
			} else if incorrect {
				t.Kind = "invalid"
				t.Message = "undefined escape sequence"
			} else {
				t.Name = name.String()
			}
		default:
			t.Kind = "invalid"
			t.Message = fmt.Sprintf("illegal character '%c'", c)
			i++
			column++
		}
		t.Spelling = source[start:i]
		tokens = append(tokens, t)
	}
	return append(tokens, Token{Kind: "eof", Position: Position{line, column}, Whitespace: space})
}

type Operator struct{ Priority, Left, Right int }

var infixOperators = map[string]Operator{
	":-": {1200, 1199, 1199}, ";": {1100, 1099, 1100}, "->": {1050, 1049, 1050}, ",": {1000, 999, 1000},
	"=": {700, 699, 699}, "\\=": {700, 699, 699}, "==": {700, 699, 699}, "\\==": {700, 699, 699}, "is": {700, 699, 699}, "=:=": {700, 699, 699}, "=\\=": {700, 699, 699}, "<": {700, 699, 699}, ">": {700, 699, 699}, "=<": {700, 699, 699}, ">=": {700, 699, 699}, "=..": {700, 699, 699},
	"+": {500, 500, 499}, "-": {500, 500, 499}, "*": {400, 400, 399}, "/": {400, 400, 399}, "//": {400, 400, 399}, "mod": {400, 400, 399}, "rem": {400, 400, 399},
}
var prefixOperators = map[string]int{"\\+": 900, "-": 200}

type SyntaxIssue struct {
	Token   Token
	Index   int
	Message string
}
type Reader struct {
	Tokens []Token
	Index  int
	Named  map[string]*Term
	Counts map[string]int
	Order  []string
}

func (r *Reader) peek() Token { return r.Tokens[r.Index] }
func (r *Reader) take() Token {
	token := r.peek()
	if token.Kind != "eof" {
		r.Index++
	}
	return token
}
func (r *Reader) fail(token Token, index int, message string) {
	if message == "" {
		switch token.Kind {
		case "invalid":
			message = token.Message
		case "eof":
			message = "unexpected end of file"
		case "end":
			message = "unexpected end of clause"
		default:
			_, operator := infixOperators[token.Name]
			if token.Kind == "name" && operator {
				message = "operator priority clash"
			} else {
				message = "unexpected \"" + token.Spelling + "\""
			}
		}
	}
	panic(SyntaxIssue{token, index, message})
}
func (r *Reader) expect(name string) {
	index := r.Index
	token := r.take()
	if token.Kind != "punctuation" || token.Name != name {
		r.fail(token, index, "")
	}
}
func (r *Reader) canStart(t Token) bool {
	if t.Kind == "integer" || t.Kind == "variable" || t.Kind == "quoted" {
		return true
	}
	if t.Kind == "punctuation" && (t.Name == "(" || t.Name == "[") {
		return true
	}
	if t.Kind == "name" {
		_, infix := infixOperators[t.Name]
		_, prefix := prefixOperators[t.Name]
		return !infix || prefix
	}
	return false
}
func (r *Reader) term(limit int) (*Term, int) {
	left, priority := r.primary(limit)
	for {
		next := r.peek()
		op, ok := infixOperators[next.Name]
		if !ok || next.Kind != "name" && (next.Kind != "punctuation" || next.Name != ",") || op.Priority > limit || priority > op.Left {
			return left, priority
		}
		r.take()
		right, _ := r.term(op.Right)
		left = compound(next.Name, left, right)
		priority = op.Priority
	}
}
func (r *Reader) primary(limit int) (*Term, int) {
	index := r.Index
	t := r.take()
	switch t.Kind {
	case "integer":
		return integer(t.Integer), 0
	case "variable":
		r.Counts[t.Name]++
		if r.Counts[t.Name] == 1 {
			r.Order = append(r.Order, t.Name)
		}
		if t.Name == "_" {
			return variable(), 0
		}
		if previous := r.Named[t.Name]; previous != nil {
			return previous, 0
		}
		v := variable()
		r.Named[t.Name] = v
		return v, 0
	case "punctuation":
		if t.Name == "(" {
			value, _ := r.term(1200)
			r.expect(")")
			return value, 0
		}
		if t.Name == "[" {
			if r.peek().Kind == "punctuation" && r.peek().Name == "]" {
				r.take()
				return atom("[]"), 0
			}
			value, _ := r.term(999)
			elements := []*Term{value}
			for r.peek().Kind == "punctuation" && r.peek().Name == "," {
				r.take()
				value, _ = r.term(999)
				elements = append(elements, value)
			}
			tail := atom("[]")
			if r.peek().Kind == "punctuation" && r.peek().Name == "|" {
				r.take()
				tail, _ = r.term(999)
			}
			r.expect("]")
			return makeList(elements, tail), 0
		}
	case "name", "quoted":
		if next := r.peek(); next.Kind == "punctuation" && next.Name == "(" && !next.Whitespace {
			r.take()
			value, _ := r.term(999)
			args := []*Term{value}
			for r.peek().Kind == "punctuation" && r.peek().Name == "," {
				r.take()
				value, _ = r.term(999)
				args = append(args, value)
			}
			r.expect(")")
			return compound(t.Name, args...), 0
		}
		if t.Kind == "name" && t.Name == "-" && r.peek().Kind == "integer" && !r.peek().Whitespace {
			return integer(-r.take().Integer), 0
		}
		if priority, ok := prefixOperators[t.Name]; t.Kind == "name" && ok && r.canStart(r.peek()) {
			if priority > limit {
				r.fail(t, index, "operator priority clash")
			}
			value, _ := r.term(priority)
			return compound(t.Name, value), priority
		}
		return atom(t.Name), 0
	}
	r.fail(t, index, "")
	return nil, 0
}
func (r *Reader) clause(query bool) *Term {
	r.Named = map[string]*Term{}
	r.Counts = map[string]int{}
	r.Order = nil
	term, _ := r.term(1200)
	index := r.Index
	t := r.take()
	if t.Kind != "end" {
		r.fail(t, index, "")
	}
	if query && r.peek().Kind != "eof" {
		r.fail(r.peek(), r.Index, "")
	}
	return term
}
func readClause(r *Reader, query bool) (term *Term, issue *SyntaxIssue) {
	defer func() {
		if failure := recover(); failure != nil {
			if error, ok := failure.(SyntaxIssue); ok {
				issue = &error
			} else {
				panic(failure)
			}
		}
	}()
	return r.clause(query), nil
}
