package main

import "strings"

type Position struct{ Line, Column int }
type FileError struct {
	Position
	Message string
}
type Comment struct {
	Text, Kind string
	Position
	Blank int
	Own   bool
}
type Token struct {
	Text, Kind string
	Position
	Blank, Index      int
	Leading, Trailing []*Comment
	OriginalTrailing  bool
}
type Lexeme struct {
	Token   *Token
	Comment *Comment
}

func (l Lexeme) line() int {
	if l.Token != nil {
		return l.Token.Line
	}
	return l.Comment.Line
}
func wordIn(words, value string) bool { return strings.Contains(" "+words+" ", " "+value+" ") }
func letter(c byte) bool              { return c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || c == '_' }
func digit(c byte) bool               { return c >= '0' && c <= '9' }
func lex(source []string) ([]*Token, []Lexeme, *FileError) {
	tokens := []*Token{}
	items := []Lexeme{}
	previousLine := 0
	for row, line := range source {
		for i := 0; i < len(line); {
			c := line[i]
			if c == ' ' {
				i++
				continue
			}
			position := Position{row + 1, i + 1}
			blank := max(0, row+1-previousLine-1)
			addToken := func(text, kind string) {
				t := &Token{Text: text, Kind: kind, Position: position, Blank: blank, Index: len(tokens)}
				tokens = append(tokens, t)
				items = append(items, Lexeme{Token: t})
				previousLine = row + 1
			}
			addComment := func(text, kind string) {
				comment := &Comment{Text: text, Kind: kind, Position: position, Blank: blank}
				items = append(items, Lexeme{Comment: comment})
				previousLine = row + 1
			}
			if strings.HasPrefix(line[i:], "//") {
				addComment(strings.TrimRight(line[i:], " "), "line")
				break
			}
			if strings.HasPrefix(line[i:], "/*") {
				end := strings.Index(line[i+2:], "*/")
				if end < 0 {
					return nil, nil, &FileError{position, "unterminated comment"}
				}
				end += i + 4
				addComment(line[i:end], "block")
				i = end
				continue
			}
			if letter(c) {
				j := i + 1
				for j < len(line) && (letter(line[j]) || digit(line[j])) {
					j++
				}
				text := line[i:j]
				kind := "identifier"
				if wordIn("int float bool string void if else while for return break continue true false switch case default", text) {
					kind = "keyword"
				}
				addToken(text, kind)
				i = j
				continue
			}
			if digit(c) {
				j := i + 1
				for j < len(line) && digit(line[j]) {
					j++
				}
				if j+1 < len(line) && line[j] == '.' && digit(line[j+1]) {
					j += 2
					for j < len(line) && digit(line[j]) {
						j++
					}
				}
				addToken(line[i:j], "number")
				i = j
				continue
			}
			if c == '"' {
				j := i + 1
				for j < len(line) && line[j] != '"' {
					if line[j] == '\\' {
						j += 2
					} else {
						j++
					}
				}
				if j >= len(line) {
					return nil, nil, &FileError{position, "unterminated string"}
				}
				j++
				addToken(line[i:j], "string")
				i = j
				continue
			}
			if i+1 < len(line) && wordIn("<= >= == != && || += -= *= /= %=", line[i:i+2]) {
				addToken(line[i:i+2], "symbol")
				i += 2
				continue
			}
			if strings.ContainsRune("+-*/%<>=!()[]{},;.?:", rune(c)) {
				addToken(string(c), "symbol")
				i++
				continue
			}
			return nil, nil, &FileError{position, "unexpected character '" + string(c) + "'"}
		}
	}
	tokens = append(tokens, &Token{Kind: "end", Position: Position{len(source) + 1, 1}, Index: len(tokens)})
	return tokens, items, nil
}
