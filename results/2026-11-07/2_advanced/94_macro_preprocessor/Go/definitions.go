package main

import (
	"fmt"
	"strings"
)

type Position struct {
	File string
	Line int
}

func (p Position) String() string { return fmt.Sprintf("%s:%d", p.File, p.Line) }

const variadicName = "__VA_ARGS__"

var builtins = map[string]bool{"__LINE__": true, "__FILE__": true, "__COUNTER__": true}

type Macro struct {
	Name               string
	Function, Variadic bool
	Parameters         []string
	Replacement        []Token
	Position
	MainFile         bool
	Expanded, Tested int
}

func (m *Macro) signature() string {
	if !m.Function {
		return m.Name
	}
	parameters := append([]string{}, m.Parameters...)
	if m.Variadic {
		parameters[len(parameters)-1] = "..."
	}
	return m.Name + "(" + strings.Join(parameters, ", ") + ")"
}
func checkName(tokens []Token, directive string) string {
	if len(tokens) == 0 {
		return "no macro name given in #" + directive + " directive"
	}
	if tokens[0].Kind != "identifier" {
		return "macro names must be identifiers"
	}
	name := tokens[0].Spelling
	if name == "defined" {
		return `"defined" cannot be used as a macro name`
	}
	if builtins[name] {
		if directive == "define" {
			return `cannot redefine builtin macro "` + name + `"`
		}
		return `cannot undefine builtin macro "` + name + `"`
	}
	return ""
}
func parseDefinition(tokens []Token, pos Position, main bool) (*Macro, string) {
	if error := checkName(tokens, "define"); error != "" {
		return nil, error
	}
	m := &Macro{Name: tokens[0].Spelling, Position: pos, MainFile: main}
	if m.Name == variadicName {
		return nil, `"__VA_ARGS__" can only appear in the expansion of a variadic macro`
	}
	index := 1
	if index < len(tokens) && tokens[index].Spelling == "(" && !tokens[index].Space {
		m.Function = true
		index++
		if index == len(tokens) {
			return nil, "missing ')' in macro parameter list"
		}
		if tokens[index].Spelling == ")" {
			index++
		} else {
			seen := map[string]bool{}
			for {
				if index == len(tokens) {
					return nil, "missing ')' in macro parameter list"
				}
				token := tokens[index]
				index++
				parameter := token.Spelling
				if parameter == "..." {
					m.Variadic = true
					parameter = variadicName
				} else if token.Kind == "identifier" {
					if parameter == variadicName {
						return nil, `"__VA_ARGS__" can only appear in the expansion of a variadic macro`
					}
					if seen[parameter] {
						return nil, `duplicate macro parameter "` + parameter + `"`
					}
				} else {
					return nil, `expected parameter name, found "` + parameter + `"`
				}
				seen[parameter] = true
				m.Parameters = append(m.Parameters, parameter)
				if index == len(tokens) {
					return nil, "missing ')' in macro parameter list"
				}
				next := tokens[index].Spelling
				index++
				if next == ")" {
					break
				}
				if m.Variadic {
					return nil, `expected ')' after "...", found "` + next + `"`
				}
				if next != "," {
					return nil, `expected ',' or ')', found "` + next + `"`
				}
			}
		}
	}
	m.Replacement = copyTokens(tokens[index:])
	if len(m.Replacement) > 0 {
		m.Replacement[0].Space = false
		if m.Replacement[0].Spelling == "##" || m.Replacement[len(m.Replacement)-1].Spelling == "##" {
			return nil, "'##' cannot appear at either end of a macro expansion"
		}
	}
	parameters := map[string]bool{}
	for _, parameter := range m.Parameters {
		parameters[parameter] = true
	}
	for i, token := range m.Replacement {
		if token.Kind == "identifier" && token.Spelling == variadicName && !m.Variadic {
			return nil, `"__VA_ARGS__" can only appear in the expansion of a variadic macro`
		}
		if token.Spelling == "#" && m.Function && (i+1 == len(m.Replacement) || m.Replacement[i+1].Kind != "identifier" || !parameters[m.Replacement[i+1].Spelling]) {
			return nil, "'#' is not followed by a macro parameter"
		}
	}
	return m, ""
}
func (m *Macro) identical(other *Macro) bool {
	if m.Function != other.Function || m.Variadic != other.Variadic || len(m.Parameters) != len(other.Parameters) || len(m.Replacement) != len(other.Replacement) {
		return false
	}
	for i, p := range m.Parameters {
		if p != other.Parameters[i] {
			return false
		}
	}
	for i, t := range m.Replacement {
		u := other.Replacement[i]
		if t.Spelling != u.Spelling || t.Space != u.Space {
			return false
		}
	}
	return true
}
