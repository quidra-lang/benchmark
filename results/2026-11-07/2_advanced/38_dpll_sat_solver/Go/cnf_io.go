package main

import (
	"fmt"
	"regexp"
	"strings"
)

var numberPattern = regexp.MustCompile(`^(0|[1-9][0-9]*)$`)
var literalPattern = regexp.MustCompile(`^(0|-?[1-9][0-9]*)$`)

func validNumber(token string) bool { return len(token) <= 6 && numberPattern.MatchString(token) }
func validLiteral(token string) bool {
	digits := strings.TrimPrefix(token, "-")
	return len(digits) <= 6 && literalPattern.MatchString(token)
}

type Formula struct {
	Variables int
	Clauses   [][]int
}

func readDimacs(filename string) (Formula, string) {
	formula := Formula{}
	declared := -1
	partial := []int{}
	for index, line := range readLines("input/" + filename) {
		number := index + 1
		tokens := strings.Fields(line)
		if strings.HasPrefix(line, "c") || len(tokens) == 0 {
			continue
		}
		if tokens[0] == "p" {
			if declared >= 0 {
				return formula, fmt.Sprintf("duplicate header at line %d", number)
			}
			if len(tokens) != 4 || tokens[1] != "cnf" || !validNumber(tokens[2]) || !validNumber(tokens[3]) {
				return formula, fmt.Sprintf("bad header at line %d", number)
			}
			formula.Variables = integer(tokens[2])
			declared = integer(tokens[3])
			continue
		}
		if declared < 0 {
			return formula, "missing header"
		}
		for _, token := range tokens {
			if !validLiteral(token) {
				return formula, fmt.Sprintf("bad token %s at line %d", token, number)
			}
			literal := integer(token)
			if abs(literal) > formula.Variables {
				return formula, fmt.Sprintf("literal out of range %s at line %d", token, number)
			}
			if literal != 0 {
				partial = append(partial, literal)
			} else {
				formula.Clauses = append(formula.Clauses, partial)
				partial = []int{}
			}
		}
	}
	if declared < 0 {
		return formula, "missing header"
	}
	if len(partial) > 0 {
		return formula, "unterminated clause"
	}
	if len(formula.Clauses) != declared {
		return formula, fmt.Sprintf("clause count mismatch header=%d found=%d", declared, len(formula.Clauses))
	}
	return formula, ""
}
func modelLines(model []bool) []string {
	tokens := []string{}
	for v := 1; v < len(model); v++ {
		literal := v
		if !model[v] {
			literal = -v
		}
		tokens = append(tokens, fmt.Sprint(literal))
	}
	tokens = append(tokens, "0")
	lines := []string{}
	for start := 0; start < len(tokens); start += 10 {
		lines = append(lines, "v "+strings.Join(tokens[start:min(start+10, len(tokens))], " "))
	}
	return lines
}
