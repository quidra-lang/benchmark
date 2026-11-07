package main

import (
	"strconv"
	"strings"
)

type Position struct{ Line, Column int }

func earlier(a, b Position) bool  { return a.Line < b.Line || a.Line == b.Line && a.Column < b.Column }
func (p Position) String() string { return strconv.Itoa(p.Line) + ":" + strconv.Itoa(p.Column) }

type Token struct {
	Kind, Spelling string
	Integer        int64
	Position
}
type CompileError struct {
	Kind, Message string
	Position
}

func wordIn(words, value string) bool {
	for _, word := range strings.Fields(words) {
		if word == value {
			return true
		}
	}
	return false
}
func letter(c byte) bool { return c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || c == '_' }
func digit(c byte) bool  { return c >= '0' && c <= '9' }
func tokenize(lines []string, firstLine int) ([]Token, *CompileError) {
	source := strings.Join(lines, "\n") + "\n"
	positions := make([]Position, len(source))
	line, column := firstLine, 1
	for i := range source {
		positions[i] = Position{line, column}
		if source[i] == '\n' {
			line++
			column = 1
		} else {
			column++
		}
	}
	tokens := []Token{}
	for i := 0; i < len(source); {
		c := source[i]
		if c == ' ' || c == '\n' {
			i++
			continue
		}
		start := i
		pos := positions[i]
		if strings.HasPrefix(source[i:], "//") {
			for i < len(source) && source[i] != '\n' {
				i++
			}
			continue
		}
		if strings.HasPrefix(source[i:], "/*") {
			end := strings.Index(source[i+2:], "*/")
			if end < 0 {
				return nil, &CompileError{"lexical", "unterminated comment", pos}
			}
			i += end + 4
			continue
		}
		if letter(c) {
			i++
			for i < len(source) && (letter(source[i]) || digit(source[i])) {
				i++
			}
			spelling := source[start:i]
			kind := "identifier"
			if wordIn("int bool void true false if else while for break continue return print read", spelling) {
				kind = spelling
			}
			tokens = append(tokens, Token{Kind: kind, Spelling: spelling, Position: pos})
			continue
		}
		if digit(c) {
			i++
			for i < len(source) && digit(source[i]) {
				i++
			}
			spelling := source[start:i]
			digits := strings.TrimLeft(spelling, "0")
			if len(digits) > 10 || len(digits) == 10 && digits > "2147483647" {
				return nil, &CompileError{"lexical", "integer literal too large", pos}
			}
			value, _ := strconv.ParseInt(spelling, 10, 64)
			tokens = append(tokens, Token{Kind: "integer", Spelling: spelling, Integer: value, Position: pos})
			continue
		}
		if i+1 < len(source) && wordIn("<= >= == != && ||", source[i:i+2]) {
			spelling := source[i : i+2]
			tokens = append(tokens, Token{Kind: spelling, Spelling: spelling, Position: pos})
			i += 2
			continue
		}
		if strings.ContainsRune("+-*/%<>=!(){}[],;", rune(c)) {
			spelling := string(c)
			tokens = append(tokens, Token{Kind: spelling, Spelling: spelling, Position: pos})
			i++
			continue
		}
		return nil, &CompileError{"lexical", "unexpected character '" + string(c) + "'", pos}
	}
	tokens = append(tokens, Token{Kind: "END", Position: Position{firstLine + len(lines) - 1, len(lines[len(lines)-1]) + 1}})
	return tokens, nil
}
