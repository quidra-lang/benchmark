package main

import "strings"

type Token struct {
	Kind, Spelling string
	Line           int
	Space          bool
	Hide           map[string]bool
}
type LogicalLine struct {
	Tokens     []Token
	Start, End int
}

var punctuators = strings.Fields("... <<= >>= -> ++ -- << >> <= >= == != && || *= /= %= += -= &= ^= |= ## [ ] ( ) { } . & * + - ~ ! / % < > ^ | ? : ; = , #")

func identifierStart(c byte) bool { return c == '_' || c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' }
func digit(c byte) bool           { return c >= '0' && c <= '9' }
func wordIn(words, value string) bool {
	for _, word := range strings.Fields(words) {
		if word == value {
			return true
		}
	}
	return false
}
func readToken(source string, index int, header bool) (string, string, int) {
	c := source[index]
	n := len(source)
	if header && c == '<' {
		end := strings.IndexByte(source[index+1:], '>')
		newline := strings.IndexByte(source[index+1:], '\n')
		if end >= 0 && (newline < 0 || end < newline) {
			end += index + 2
			return "header", source[index:end], end
		}
	}
	if identifierStart(c) {
		end := index + 1
		for end < n && (identifierStart(source[end]) || digit(source[end])) {
			end++
		}
		return "identifier", source[index:end], end
	}
	if digit(c) || c == '.' && index+1 < n && digit(source[index+1]) {
		end := index + 1
		for end < n {
			if strings.ContainsRune("eEpP", rune(source[end])) && end+1 < n && (source[end+1] == '+' || source[end+1] == '-') {
				end += 2
			} else if identifierStart(source[end]) || digit(source[end]) || source[end] == '.' {
				end++
			} else {
				break
			}
		}
		return "number", source[index:end], end
	}
	if c == '\'' || c == '"' {
		end := index + 1
		for end < n && source[end] != '\n' {
			if source[end] == c {
				kind := "character"
				if c == '"' {
					kind = "string"
				}
				return kind, source[index : end+1], end + 1
			}
			if source[end] == '\\' && end+1 < n && source[end+1] != '\n' {
				end += 2
			} else {
				end++
			}
		}
	}
	for _, punctuator := range punctuators {
		if strings.HasPrefix(source[index:], punctuator) {
			return "punctuator", punctuator, index + len(punctuator)
		}
	}
	return "other", source[index : index+1], index + 1
}
func scan(source string, positions []int, start int) []LogicalLine {
	lines := []LogicalLine{}
	tokens := []Token{}
	spaced := true
	for index := 0; index < len(source); {
		switch {
		case source[index] == ' ':
			spaced = true
			index++
		case source[index] == '\n':
			end := positions[index]
			lines = append(lines, LogicalLine{tokens, start, end})
			tokens = nil
			start = end + 1
			spaced = true
			index++
		case strings.HasPrefix(source[index:], "/*"):
			end := strings.Index(source[index+2:], "*/")
			if end < 0 {
				index = len(source)
			} else {
				index += end + 4
			}
			spaced = true
		case strings.HasPrefix(source[index:], "//"):
			end := strings.IndexByte(source[index:], '\n')
			if end < 0 {
				index = len(source)
			} else {
				index += end
			}
			spaced = true
		default:
			header := len(tokens) == 2 && tokens[0].Spelling == "#" && tokens[1].Spelling == "include"
			kind, spelling, end := readToken(source, index, header)
			tokens = append(tokens, Token{Kind: kind, Spelling: spelling, Line: positions[index], Space: spaced})
			index = end
			spaced = false
		}
	}
	if len(tokens) > 0 {
		lines = append(lines, LogicalLine{tokens, start, positions[len(positions)-1]})
	}
	return lines
}
func lexSource(source string) []LogicalLine {
	characters := []byte{}
	positions := []int{}
	line := 1
	for i := 0; i < len(source); {
		if i+1 < len(source) && source[i] == '\\' && source[i+1] == '\n' {
			i += 2
			line++
			continue
		}
		c := source[i]
		characters = append(characters, c)
		positions = append(positions, line)
		if c == '\n' {
			line++
		}
		i++
	}
	return scan(string(characters), positions, 1)
}
func lexDefinition(source string, line int) []Token {
	source += "\n"
	positions := make([]int, len(source))
	for i := range positions {
		positions[i] = line
	}
	out := []Token{}
	for _, logical := range scan(source, positions, line) {
		out = append(out, logical.Tokens...)
	}
	return out
}
func render(tokens []Token) string {
	var out strings.Builder
	for i, token := range tokens {
		if i > 0 && token.Space {
			out.WriteByte(' ')
		}
		out.WriteString(token.Spelling)
	}
	return out.String()
}
func singleToken(source string) (string, bool) {
	if source == "" || strings.HasPrefix(source, "//") || strings.HasPrefix(source, "/*") {
		return "", false
	}
	kind, _, end := readToken(source, 0, false)
	return kind, end == len(source)
}
func copyTokens(tokens []Token) []Token { return append([]Token{}, tokens...) }
