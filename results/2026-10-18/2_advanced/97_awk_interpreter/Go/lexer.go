package main

import (
	"strconv"
	"strings"
)

type Position struct{ Line, Column int }

func (p Position) String() string { return strconv.Itoa(p.Line) + ":" + strconv.Itoa(p.Column) }

type SyntaxIssue struct{ Position Position }
type Token struct {
	Kind, Spelling, Text string
	Number               int64
	Position             Position
}

func letter(c byte) bool { return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' }
func digit(c byte) bool  { return c >= '0' && c <= '9' }
func wordIn(words, value string) bool {
	for _, word := range strings.Fields(words) {
		if word == value {
			return true
		}
	}
	return false
}
func decimal(text string) int64 {
	n, err := strconv.ParseInt(text, 10, 64)
	if err != nil {
		panic(err)
	}
	return n
}
func tokenize(source string) []Token {
	tokens := []Token{}
	line, column := 1, 1
	for i := 0; i < len(source); {
		c := source[i]
		position := Position{line, column}
		if c == ' ' {
			i++
			column++
			continue
		}
		if c == '\\' && i+1 < len(source) && source[i+1] == '\n' {
			i += 2
			line++
			column = 1
			continue
		}
		if c == '#' {
			for i < len(source) && source[i] != '\n' {
				i++
				column++
			}
			continue
		}
		if c == '\n' {
			tokens = append(tokens, Token{Kind: "newline", Spelling: "\n", Position: position})
			i++
			line++
			column = 1
			continue
		}
		if digit(c) {
			start := i
			for i < len(source) && digit(source[i]) {
				i++
				column++
			}
			text := source[start:i]
			tokens = append(tokens, Token{Kind: "number", Spelling: text, Number: decimal(text), Position: position})
			continue
		}
		if letter(c) || c == '_' {
			start := i
			for i < len(source) && (letter(source[i]) || digit(source[i]) || source[i] == '_') {
				i++
				column++
			}
			text := source[start:i]
			kind := "name"
			if wordIn("BEGIN END function if else while for do break continue next exit return delete in getline print printf", text) {
				kind = "keyword"
			} else if wordIn("length substr index split sprintf toupper tolower close int", text) {
				kind = "builtin"
			} else if i < len(source) && source[i] == '(' {
				kind = "function_name"
			}
			tokens = append(tokens, Token{Kind: kind, Spelling: text, Position: position})
			continue
		}
		if c == '"' {
			start := i
			i++
			column++
			var value strings.Builder
			for {
				if i == len(source) || source[i] == '\n' {
					panic(SyntaxIssue{position})
				}
				c = source[i]
				i++
				column++
				if c == '"' {
					break
				}
				if c == '\\' {
					slash := Position{line, column - 1}
					if i == len(source) {
						panic(SyntaxIssue{position})
					}
					c = source[i]
					i++
					column++
					switch c {
					case 'n':
						c = '\n'
					case 't':
						c = '\t'
					case '\\', '"', '/':
					default:
						panic(SyntaxIssue{slash})
					}
				}
				value.WriteByte(c)
			}
			tokens = append(tokens, Token{Kind: "string", Spelling: source[start:i], Text: value.String(), Position: position})
			continue
		}
		symbol := ""
		if i+1 < len(source) && wordIn("+= -= *= /= %= ^= == <= >= != ++ -- && || >>", source[i:i+2]) {
			symbol = source[i : i+2]
		} else if strings.ContainsRune("+-*/%^!><?:=()[]{},;$", rune(c)) {
			symbol = source[i : i+1]
		}
		if symbol == "" {
			panic(SyntaxIssue{position})
		}
		tokens = append(tokens, Token{Kind: "symbol", Spelling: symbol, Position: position})
		i += len(symbol)
		column += len(symbol)
	}
	return append(tokens, Token{Kind: "end", Position: Position{strings.Count(source, "\n") + 1, 1}})
}
