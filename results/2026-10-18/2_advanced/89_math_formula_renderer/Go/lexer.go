package main

import "strings"

type Token struct {
	Kind, Value string
	Column      int
}
type Issue struct {
	Column  int
	Message string
}
type SymbolInfo struct{ Display, Type string }

var greekNames = strings.Fields("alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi pi rho sigma tau upsilon phi chi psi omega Gamma Delta Theta Lambda Xi Pi Sigma Upsilon Phi Psi Omega")
var greek = func() map[string]bool {
	m := map[string]bool{}
	for _, name := range greekNames {
		m[name] = true
	}
	return m
}()
var symbolCommands = func() map[string]SymbolInfo {
	m := map[string]SymbolInfo{}
	for _, name := range greekNames {
		m["\\"+name] = SymbolInfo{name, "ordinary"}
	}
	for _, name := range strings.Fields("sin cos tan log ln exp det lim max min sum prod int") {
		m["\\"+name] = SymbolInfo{name, "operator"}
	}
	for name, display := range map[string]string{"cdot": "*", "times": "x", "pm": "+-", "mp": "-+"} {
		m["\\"+name] = SymbolInfo{display, "binary"}
	}
	for name, display := range map[string]string{"leq": "<=", "geq": ">=", "neq": "!=", "approx": "~=", "to": "->"} {
		m["\\"+name] = SymbolInfo{display, "relation"}
	}
	for name, display := range map[string]string{"infty": "oo", "ldots": "...", "cdots": "...", "quad": "  ", ",": " "} {
		m["\\"+name] = SymbolInfo{display, "ordinary"}
	}
	m[`\{`] = SymbolInfo{"{", "open"}
	m[`\}`] = SymbolInfo{"}", "close"}
	return m
}()
var commandNames = func() map[string]bool {
	m := map[string]bool{}
	for command := range symbolCommands {
		if len(command) > 2 {
			m[command[1:]] = true
		}
	}
	return m
}()

func isLetter(c byte) bool                  { return c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' }
func isDigit(c byte) bool                   { return c >= '0' && c <= '9' }
func containsWord(words, value string) bool { return strings.Contains(" "+words+" ", " "+value+" ") }
func tokenize(line string) ([]Token, *Issue) {
	tokens := []Token{}
	for i := 0; i < len(line); {
		c := line[i]
		column := i + 1
		if c == ' ' {
			i++
			continue
		}
		if isLetter(c) {
			j := i + 1
			for j < len(line) && isLetter(line[j]) {
				j++
			}
			tokens = append(tokens, Token{"identifier", line[i:j], column})
			i = j
			continue
		}
		if isDigit(c) {
			j := i + 1
			for j < len(line) && isDigit(line[j]) {
				j++
			}
			if j+1 < len(line) && line[j] == '.' && isDigit(line[j+1]) {
				j += 2
				for j < len(line) && isDigit(line[j]) {
					j++
				}
			}
			tokens = append(tokens, Token{"number", line[i:j], column})
			i = j
			continue
		}
		if strings.ContainsRune("+-*/=<>:()[],;.!|'", rune(c)) {
			tokens = append(tokens, Token{"symbol", string(c), column})
			i++
			continue
		}
		if strings.ContainsRune("{}^_&", rune(c)) {
			tokens = append(tokens, Token{string(c), string(c), column})
			i++
			continue
		}
		if c != '\\' {
			return nil, &Issue{column, "invalid character " + string(c)}
		}
		if i+1 < len(line) && line[i+1] == '\\' {
			tokens = append(tokens, Token{"newline", "", column})
			i += 2
			continue
		}
		if i+1 < len(line) && strings.ContainsRune("{},", rune(line[i+1])) {
			tokens = append(tokens, Token{"command", line[i : i+2], column})
			i += 2
			continue
		}
		j := i + 1
		for j < len(line) && isLetter(line[j]) {
			j++
		}
		if j == i+1 {
			return nil, &Issue{column, "invalid command"}
		}
		name := line[i+1 : j]
		i = j
		if containsWord("text begin end tag label eqref", name) {
			for i < len(line) && line[i] == ' ' {
				i++
			}
			if i == len(line) || line[i] != '{' {
				return nil, &Issue{i + 1, "expected {"}
			}
			end := strings.IndexByte(line[i+1:], '}')
			if end < 0 {
				return nil, &Issue{column, "unterminated argument"}
			}
			end += i + 1
			value := line[i+1 : end]
			i = end + 1
			if (name == "begin" || name == "end") && !containsWord("matrix pmatrix bmatrix vmatrix cases", value) {
				return nil, &Issue{column, `unknown environment "` + value + `"`}
			}
			tokens = append(tokens, Token{name, value, column})
			continue
		}
		value := "\\" + name
		if _, ok := symbolCommands[value]; ok {
			tokens = append(tokens, Token{"command", value, column})
		} else if containsWord("overline hat vec dot tilde overbrace underbrace", name) {
			tokens = append(tokens, Token{"accent", name, column})
		} else if containsWord("frac binom overset underset sqrt left right", name) {
			tokens = append(tokens, Token{name, "", column})
		} else {
			return nil, &Issue{column, "unknown command \\" + name}
		}
	}
	return tokens, nil
}
