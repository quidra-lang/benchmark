package main

import (
	"bufio"
	"os"
	"regexp"
	"strconv"
	"strings"
)

type ModelError struct {
	Line    int
	Message string
}
type Term struct {
	Name        string
	Coefficient Fraction
}
type Constraint struct {
	Name, Comparison string
	Line             int
	Terms            []Term
	RHS              Fraction
	Coefficients     []Fraction
}
type BoundLine struct {
	Line         int
	Name, Kind   string
	Lower, Upper *Fraction
}
type Declaration struct {
	Line  int
	Names []string
}
type RawModel struct {
	Name, Direction    string
	Objective          []Term
	Constraints        []Constraint
	Bounds             []BoundLine
	Integers, Binaries []Declaration
	Err                *ModelError
}
type Settings struct {
	Level, Limit int
	Logs, Limits map[string]int
}
type Record struct {
	Line int
	Text string
}

var namePattern = regexp.MustCompile(`^[a-z][a-z0-9_]*$`)

func isName(word string) bool {
	return namePattern.MatchString(word) && !wordIn("bounds integer binary free inf", word)
}
func wordIn(words, value string) bool {
	for _, word := range strings.Fields(words) {
		if word == value {
			return true
		}
	}
	return false
}
func parseExpression(words []string) ([]Term, bool) {
	out := []Term{}
	position, sign := 0, int64(1)
	if len(words) > 0 && words[0] == "-" {
		position++
		sign = -1
	}
	for position < len(words) {
		coefficient, ok := readNumber(words[position], false)
		name := ""
		if ok {
			if position+1 == len(words) || !isName(words[position+1]) {
				return nil, false
			}
			name = words[position+1]
			position += 2
		} else if isName(words[position]) {
			coefficient = integer(1)
			name = words[position]
			position++
		} else {
			return nil, false
		}
		out = append(out, Term{name, coefficient.mul(integer(sign))})
		if position == len(words) {
			return out, true
		}
		if words[position] != "+" && words[position] != "-" {
			return nil, false
		}
		sign = 1
		if words[position] == "-" {
			sign = -1
		}
		position++
	}
	return nil, false
}
func namedExpression(words []string) (string, []Term, bool) {
	if len(words) < 2 || !strings.HasSuffix(words[0], ":") {
		return "", nil, false
	}
	name := strings.TrimSuffix(words[0], ":")
	if !isName(name) {
		return "", nil, false
	}
	terms, ok := parseExpression(words[1:])
	return name, terms, ok
}
func parseConstraint(words []string, line int) (Constraint, bool) {
	if len(words) < 4 || !wordIn("<= >= =", words[len(words)-2]) {
		return Constraint{}, false
	}
	rhs, ok := readNumber(words[len(words)-1], true)
	if !ok {
		return Constraint{}, false
	}
	name, terms, ok := namedExpression(words[:len(words)-2])
	return Constraint{Name: name, Comparison: words[len(words)-2], Line: line, Terms: terms, RHS: rhs}, ok
}
func parseBound(words []string, line int) (BoundLine, bool) {
	n := len(words)
	if n == 2 && isName(words[0]) && words[1] == "free" {
		return BoundLine{Line: line, Name: words[0], Kind: "both"}, true
	}
	if n == 3 && isName(words[0]) {
		value, ok := readNumber(words[2], true)
		b := BoundLine{Line: line, Name: words[0]}
		switch words[1] {
		case ">=":
			if ok || words[2] == "-inf" {
				b.Kind = "lower"
				if ok {
					b.Lower = finite(value)
				}
				return b, true
			}
		case "<=":
			if ok || words[2] == "inf" {
				b.Kind = "upper"
				if ok {
					b.Upper = finite(value)
				}
				return b, true
			}
		case "=":
			if ok {
				b.Kind = "both"
				b.Lower = finite(value)
				b.Upper = finite(value)
				return b, true
			}
		}
	}
	if n == 5 && words[1] == "<=" && words[3] == "<=" && isName(words[2]) {
		lower, lo := readNumber(words[0], true)
		upper, up := readNumber(words[4], true)
		if (lo || words[0] == "-inf") && (up || words[4] == "inf") {
			b := BoundLine{Line: line, Name: words[2], Kind: "both"}
			if lo {
				b.Lower = finite(lower)
			}
			if up {
				b.Upper = finite(upper)
			}
			return b, true
		}
	}
	return BoundLine{}, false
}
func parseBlock(name string, body []Record, endLine int) RawModel {
	m := RawModel{Name: name}
	state := "A"
	for _, record := range body {
		words := strings.Split(record.Text, " ")
		accepted := false
		switch state {
		case "A":
			if record.Text == "maximize" || record.Text == "minimize" {
				m.Direction = record.Text
				state = "B"
				accepted = true
			}
		case "B":
			_, terms, ok := namedExpression(words)
			if ok {
				m.Objective = terms
				state = "C"
				accepted = true
			}
		case "C":
			if record.Text == "subject to" {
				state = "D"
				accepted = true
			}
		case "D", "E":
			if state == "E" && wordIn("bounds integer binary", record.Text) {
				state = map[string]string{"bounds": "F", "integer": "G", "binary": "H"}[record.Text]
				accepted = true
			} else if c, ok := parseConstraint(words, record.Line); ok {
				m.Constraints = append(m.Constraints, c)
				state = "E"
				accepted = true
			}
		case "F":
			if record.Text == "integer" || record.Text == "binary" {
				state = "G"
				if record.Text == "binary" {
					state = "H"
				}
				accepted = true
			} else if b, ok := parseBound(words, record.Line); ok {
				m.Bounds = append(m.Bounds, b)
				accepted = true
			}
		case "G", "H":
			if state == "G" && record.Text == "binary" {
				state = "H"
				accepted = true
			} else {
				valid := true
				for _, word := range words {
					if !isName(word) {
						valid = false
					}
				}
				if valid {
					d := Declaration{record.Line, words}
					if state == "G" {
						m.Integers = append(m.Integers, d)
					} else {
						m.Binaries = append(m.Binaries, d)
					}
					accepted = true
				}
			}
		}
		if !accepted {
			m.Err = &ModelError{record.Line, "syntax error"}
			return m
		}
	}
	if wordIn("A B C D", state) {
		m.Err = &ModelError{endLine, "syntax error"}
	}
	return m
}
func readLines(path string) []string {
	f, err := os.Open(path)
	if err != nil {
		panic(err)
	}
	defer f.Close()
	lines := []string{}
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		lines = append(lines, scanner.Text())
	}
	if err = scanner.Err(); err != nil {
		panic(err)
	}
	return lines
}
func readModels() []RawModel {
	out := []RawModel{}
	name := ""
	body := []Record{}
	for i, line := range readLines("input/models.lp") {
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if name == "" {
			name = strings.Split(line, " ")[1]
			body = nil
		} else if line == "end" {
			out = append(out, parseBlock(name, body, i+1))
			name = ""
		} else {
			body = append(body, Record{i + 1, line})
		}
	}
	return out
}
func readSettings() Settings {
	lines := readLines("input/params.txt")
	level, _ := strconv.Atoi(strings.Split(lines[0], " ")[1])
	limit, _ := strconv.Atoi(strings.Split(lines[1], " ")[1])
	s := Settings{level, limit, map[string]int{}, map[string]int{}}
	for _, line := range lines[2:] {
		a := strings.Split(line, " ")
		value, _ := strconv.Atoi(a[2])
		if a[0] == "log" {
			s.Logs[a[1]] = value
		} else {
			s.Limits[a[1]] = value
		}
	}
	return s
}
