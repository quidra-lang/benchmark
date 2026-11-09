package main

import (
	"fmt"
	"os"
	"slices"
	"strings"
)

type Grammar struct {
	Order          []string
	Rules          map[string][][]string
	Start          string
	Declared       map[string]bool
	HasDeclaration bool
	Words          map[string]int
	Diagnostics    []string
}
type LexToken struct {
	Kind, Value string
	Start, End  int
}
type ParsedLine struct {
	Kind, Symbol string
	Alternatives [][]string
	Words        []string
	Error        int
}

func isNonterminal(s string) bool { return strings.HasPrefix(s, "<") && strings.HasSuffix(s, ">") }
func letter(b byte) bool          { return b >= 'A' && b <= 'Z' || b >= 'a' && b <= 'z' }
func wordCharacter(b byte) bool   { return letter(b) || b >= '0' && b <= '9' || b == '_' }
func lexLine(line string) []LexToken {
	tokens := []LexToken{}
	for i := 0; i < len(line); {
		if line[i] == ' ' {
			i++
			continue
		}
		if line[i] == '#' {
			break
		}
		start := i
		kind, value := "invalid", string(line[i])
		end := i + 1
		switch {
		case line[i] == '<':
			j := i + 1
			if j < len(line) && letter(line[j]) {
				j++
				for j < len(line) && wordCharacter(line[j]) {
					j++
				}
				if j < len(line) && line[j] == '>' {
					kind, value, end = "nonterminal", line[i:j+1], j+1
				}
			}
		case line[i] == '"':
			j := i + 1
			for j < len(line) && line[j] != ' ' && line[j] != '"' {
				j++
			}
			if j > i+1 && j < len(line) && line[j] == '"' {
				kind, value, end = "terminal", line[i+1:j], j+1
			}
		case letter(line[i]):
			j := i + 1
			for j < len(line) && wordCharacter(line[j]) {
				j++
			}
			kind, value, end = "word", line[i:j], j
		case strings.HasPrefix(line[i:], "::="):
			kind, value, end = "definition", "::=", i+3
		case line[i] == '|':
			kind, value = "separator", "|"
		case line[i] == '%':
			j := i + 1
			for j < len(line) && letter(line[j]) {
				j++
			}
			name := line[i+1 : j]
			if name == "empty" || name == "start" || name == "token" {
				kind, value, end = "directive", "%"+name, j
			}
		}
		i = end
		tokens = append(tokens, LexToken{kind, value, start + 1, end})
		if kind == "invalid" {
			break
		}
	}
	return tokens
}
func errorColumn(tokens []LexToken, cursor int) int {
	if cursor < len(tokens) {
		return tokens[cursor].Start
	}
	return tokens[len(tokens)-1].End + 1
}
func alternativeList(tokens []LexToken, cursor int) ([][]string, int) {
	alternatives := [][]string{}
	for {
		if cursor >= len(tokens) {
			return nil, errorColumn(tokens, cursor)
		}
		first := tokens[cursor]
		rhs := []string{}
		if first.Kind == "directive" && first.Value == "%empty" {
			cursor++
			if cursor < len(tokens) && tokens[cursor].Kind != "separator" {
				return nil, errorColumn(tokens, cursor)
			}
		} else if first.Kind == "nonterminal" || first.Kind == "word" || first.Kind == "terminal" {
			for cursor < len(tokens) {
				kind := tokens[cursor].Kind
				if kind != "nonterminal" && kind != "word" && kind != "terminal" {
					break
				}
				rhs = append(rhs, tokens[cursor].Value)
				cursor++
			}
		} else {
			return nil, errorColumn(tokens, cursor)
		}
		alternatives = append(alternatives, rhs)
		if cursor == len(tokens) {
			return alternatives, 0
		}
		if tokens[cursor].Kind != "separator" {
			return nil, errorColumn(tokens, cursor)
		}
		cursor++
	}
}
func parseLine(tokens []LexToken) ParsedLine {
	if len(tokens) == 0 {
		return ParsedLine{Kind: "blank"}
	}
	first := tokens[0]
	switch {
	case first.Kind == "nonterminal":
		if len(tokens) < 2 {
			return ParsedLine{Error: errorColumn(tokens, 1)}
		}
		if tokens[1].Kind != "definition" {
			return ParsedLine{Error: errorColumn(tokens, 1)}
		}
		alts, e := alternativeList(tokens, 2)
		return ParsedLine{Kind: "rule", Symbol: first.Value, Alternatives: alts, Error: e}
	case first.Kind == "separator":
		alts, e := alternativeList(tokens, 1)
		return ParsedLine{Kind: "continuation", Alternatives: alts, Error: e}
	case first.Kind == "directive" && first.Value == "%start":
		if len(tokens) < 2 {
			return ParsedLine{Error: errorColumn(tokens, 1)}
		}
		if tokens[1].Kind != "nonterminal" {
			return ParsedLine{Error: errorColumn(tokens, 1)}
		}
		if len(tokens) > 2 {
			return ParsedLine{Error: errorColumn(tokens, 2)}
		}
		return ParsedLine{Kind: "start", Symbol: tokens[1].Value}
	case first.Kind == "directive" && first.Value == "%token":
		if len(tokens) < 2 {
			return ParsedLine{Error: errorColumn(tokens, 1)}
		}
		words := []string{}
		for i, t := range tokens[1:] {
			if t.Kind != "word" {
				return ParsedLine{Error: errorColumn(tokens, i+1)}
			}
			words = append(words, t.Value)
		}
		return ParsedLine{Kind: "declaration", Words: words}
	}
	return ParsedLine{Error: errorColumn(tokens, 0)}
}
func notation(rhs []string) string {
	if len(rhs) == 0 {
		return "%empty"
	}
	return strings.Join(rhs, " ")
}
func productionNotation(lhs string, rhs []string) string { return lhs + " -> " + notation(rhs) }
func readLines(path string) []string {
	data, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	return strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
}
func parseGrammar() Grammar {
	g := Grammar{Rules: map[string][][]string{}, Declared: map[string]bool{}, Words: map[string]int{}}
	attachment := ""
	for i, line := range readLines("input/grammar.bnf") {
		tokens := lexLine(line)
		parsed := parseLine(tokens)
		lineNumber := i + 1
		if parsed.Error > 0 {
			g.Diagnostics = append(g.Diagnostics, fmt.Sprintf("line %d: syntax error at column %d", lineNumber, parsed.Error))
			attachment = ""
			continue
		}
		if parsed.Kind == "blank" {
			continue
		}
		symbol := parsed.Symbol
		switch parsed.Kind {
		case "rule":
			attachment = symbol
			if _, ok := g.Rules[symbol]; !ok {
				g.Order = append(g.Order, symbol)
				g.Rules[symbol] = [][]string{}
			}
		case "continuation":
			if attachment == "" {
				g.Diagnostics = append(g.Diagnostics, fmt.Sprintf("line %d: continuation without a rule", lineNumber))
				continue
			}
			symbol = attachment
		case "start":
			attachment = ""
			if g.Start == "" {
				g.Start = symbol
			} else {
				g.Diagnostics = append(g.Diagnostics, fmt.Sprintf("line %d: duplicate %%start", lineNumber))
			}
		case "declaration":
			attachment = ""
			g.HasDeclaration = true
			for _, word := range parsed.Words {
				g.Declared[word] = true
			}
		}
		if parsed.Kind == "rule" || parsed.Kind == "continuation" {
			for _, t := range tokens {
				if t.Kind == "word" && g.Words[t.Value] == 0 {
					g.Words[t.Value] = lineNumber
				}
			}
			for _, rhs := range parsed.Alternatives {
				duplicate := false
				for _, old := range g.Rules[symbol] {
					if slices.Equal(old, rhs) {
						duplicate = true
						break
					}
				}
				if duplicate {
					g.Diagnostics = append(g.Diagnostics, fmt.Sprintf("line %d: duplicate alternative %s", lineNumber, productionNotation(symbol, rhs)))
				} else {
					g.Rules[symbol] = append(g.Rules[symbol], rhs)
				}
			}
		}
	}
	if g.Start == "" {
		g.Start = g.Order[0]
	}
	return g
}
