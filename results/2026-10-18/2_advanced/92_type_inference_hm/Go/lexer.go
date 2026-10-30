package main

import (
	"strconv"
	"strings"
)

type Position struct {
	File         string
	Line, Column int
}
type Token struct {
	Kind, Spelling, Value string
	Position
	Integer int64
}

func wordIn(words, value string) bool {
	for _, word := range strings.Fields(words) {
		if word == value {
			return true
		}
	}
	return false
}
func letter(c byte) bool   { return c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' }
func digit(c byte) bool    { return c >= '0' && c <= '9' }
func (t Token) name() bool { return t.Kind == "identifier" && t.Spelling != "_" }
func lex(filename string, lines []string) []Token {
	source := strings.Join(lines, "\n")
	if len(lines) > 0 {
		source += "\n"
	}
	positions := make([]Position, len(source)+1)
	line, column := 1, 1
	for i := 0; i < len(source); i++ {
		positions[i] = Position{filename, line, column}
		if source[i] == '\n' {
			line++
			column = 1
		} else {
			column++
		}
	}
	positions[len(source)] = Position{filename, len(lines) + 1, 1}
	out := []Token{}
	for i := 0; i < len(source); {
		c := source[i]
		if c == ' ' || c == '\n' {
			i++
			continue
		}
		start := i
		token := Token{Position: positions[start]}
		if strings.HasPrefix(source[i:], "(*") {
			end := strings.Index(source[i+2:], "*)")
			if end < 0 {
				out = append(out, Token{Kind: "invalid", Value: "unterminated comment", Position: positions[start]})
				break
			}
			i += end + 4
			continue
		}
		if digit(c) {
			i++
			for i < len(source) && digit(source[i]) {
				i++
			}
			token.Spelling = source[start:i]
			token.Kind = "integer"
			digits := strings.TrimLeft(token.Spelling, "0")
			if len(digits) > 10 || len(digits) == 10 && digits > "2147483647" {
				token.Kind = "invalid"
				token.Value = "integer literal too large"
			} else {
				token.Integer, _ = strconv.ParseInt(token.Spelling, 10, 64)
			}
			out = append(out, token)
			continue
		}
		if letter(c) || c == '_' {
			i++
			for i < len(source) && (letter(source[i]) || digit(source[i]) || source[i] == '_' || source[i] == '\'') {
				i++
			}
			token.Spelling = source[start:i]
			token.Kind = "identifier"
			if wordIn("let rec and in fun if then else match with true false mod val", token.Spelling) {
				token.Kind = token.Spelling
			}
			out = append(out, token)
			continue
		}
		if c == '\'' && i+1 < len(source) && source[i+1] >= 'a' && source[i+1] <= 'z' {
			i += 2
			for i < len(source) && (letter(source[i]) || digit(source[i]) || source[i] == '_') {
				i++
			}
			token.Kind = "type_variable"
			token.Spelling = source[start:i]
			out = append(out, token)
			continue
		}
		if c == '"' {
			i++
			bad := false
			var value strings.Builder
			for i < len(source) && source[i] != '\n' && source[i] != '"' {
				if source[i] == '\\' && i+1 < len(source) && source[i+1] != '\n' {
					next := source[i+1]
					switch next {
					case 'n':
						value.WriteByte('\n')
					case 't':
						value.WriteByte('\t')
					case '\\', '"':
						value.WriteByte(next)
					default:
						bad = true
					}
					i += 2
				} else {
					value.WriteByte(source[i])
					i++
				}
			}
			token.Kind = "string"
			token.Value = value.String()
			if i == len(source) || source[i] == '\n' {
				token.Kind = "invalid"
				token.Value = "unterminated string"
			} else {
				i++
				if bad {
					token.Kind = "invalid"
					token.Value = "invalid escape sequence"
				}
			}
			token.Spelling = source[start:i]
			out = append(out, token)
			continue
		}
		found := ""
		for _, symbol := range strings.Fields(";; -> :: : || && <= >= <> ; = < > + - * / ^ ( ) [ ] , |") {
			if strings.HasPrefix(source[i:], symbol) && len(symbol) > len(found) {
				found = symbol
			}
		}
		if found != "" {
			i += len(found)
			token.Kind = found
			token.Spelling = found
		} else {
			i++
			token.Kind = "invalid"
			token.Spelling = string(c)
			token.Value = "illegal character '" + string(c) + "'"
		}
		out = append(out, token)
	}
	out = append(out, Token{Kind: "EOF", Position: positions[len(source)]})
	return out
}
