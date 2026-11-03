package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

var instructionKinds = []string{"copy", "bin", "load", "store", "goto", "if", "param", "call", "return", "read", "print"}

type Operand struct {
	Variable   string
	Constant   int64
	IsConstant bool
}

func operand(text string) Operand {
	if text[0] == '-' || text[0] >= '0' && text[0] <= '9' {
		return Operand{Constant: integer(text), IsConstant: true}
	}
	return Operand{Variable: text}
}
func constant(n int64) Operand { return Operand{Constant: n, IsConstant: true} }
func (a Operand) String() string {
	if a.IsConstant {
		return strconv.FormatInt(a.Constant, 10)
	}
	return a.Variable
}
func integer(text string) int64 {
	n, err := strconv.ParseInt(text, 10, 64)
	if err != nil {
		panic(err)
	}
	return n
}

type Expression struct {
	Kind, Operator string
	A, B           Operand
}

func (e Expression) String() string {
	if e.Kind == "load" {
		return e.Operator + "[" + e.A.String() + "]"
	}
	return e.A.String() + e.Operator + e.B.String()
}
func (e Expression) uses(name string) bool {
	return !e.A.IsConstant && e.A.Variable == name || e.Kind == "bin" && !e.B.IsConstant && e.B.Variable == name
}

type Instruction struct {
	Kind, Destination, Operator, Name string
	A, B                              Operand
	HasA                              bool
	Count, Number                     int
}

func (s *Instruction) definition() string { return s.Destination }
func (s *Instruction) operands() []*Operand {
	switch s.Kind {
	case "copy", "load", "param", "print":
		return []*Operand{&s.A}
	case "bin", "if", "store":
		return []*Operand{&s.A, &s.B}
	case "return":
		if s.HasA {
			return []*Operand{&s.A}
		}
	}
	return nil
}
func (s *Instruction) used() []string {
	out := []string{}
	for _, a := range s.operands() {
		if !a.IsConstant {
			out = append(out, a.Variable)
		}
	}
	return out
}
func (s *Instruction) expression() (Expression, bool) {
	switch s.Kind {
	case "bin":
		return Expression{Kind: "bin", Operator: s.Operator, A: s.A, B: s.B}, true
	case "load":
		return Expression{Kind: "load", Operator: s.Name, A: s.A}, true
	}
	return Expression{}, false
}
func (s *Instruction) String() string {
	switch s.Kind {
	case "copy":
		return s.Destination + " = " + s.A.String()
	case "bin":
		return s.Destination + " = " + s.A.String() + " " + s.Operator + " " + s.B.String()
	case "load":
		return s.Destination + " = " + s.Name + "[" + s.A.String() + "]"
	case "store":
		return s.Name + "[" + s.A.String() + "] = " + s.B.String()
	case "goto":
		return "goto " + s.Name
	case "if":
		return "if " + s.A.String() + " " + s.Operator + " " + s.B.String() + " goto " + s.Name
	case "param", "print":
		return s.Kind + " " + s.A.String()
	case "call":
		prefix := ""
		if s.Destination != "" {
			prefix = s.Destination + " = "
		}
		return fmt.Sprintf("%scall %s %d", prefix, s.Name, s.Count)
	case "return":
		if s.HasA {
			return "return " + s.A.String()
		}
		return "return"
	case "read":
		return "read " + s.Destination
	}
	panic("unknown instruction")
}

type CodeLine struct {
	Label       string
	Instruction *Instruction
}
type Function struct {
	Name                             string
	Parameters                       []string
	Code                             []CodeLine
	TemporarySerial, PreheaderSerial int
}
type Array struct {
	Name string
	Size int
}
type Program struct {
	Arrays    []Array
	Functions []*Function
}

func cloneFunction(f *Function) *Function {
	out := *f
	out.Parameters = append([]string{}, f.Parameters...)
	out.Code = nil
	for _, line := range f.Code {
		if line.Instruction != nil {
			copy := *line.Instruction
			line.Instruction = &copy
		}
		out.Code = append(out.Code, line)
	}
	return &out
}
func cloneProgram(p *Program) *Program {
	out := &Program{Arrays: append([]Array{}, p.Arrays...)}
	for _, f := range p.Functions {
		out.Functions = append(out.Functions, cloneFunction(f))
	}
	return out
}
func readLines(path string) []string {
	data, err := os.ReadFile(path)
	if err != nil {
		panic(err)
	}
	return strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
}
func arrayOperand(text string) (string, Operand) {
	i := strings.IndexByte(text, '[')
	return text[:i], operand(text[i+1 : len(text)-1])
}
func parseProgram() *Program {
	p := &Program{}
	var f *Function
	for _, line := range readLines("input/program.tac") {
		words := strings.Fields(line)
		if len(words) == 0 || strings.HasPrefix(words[0], "#") {
			continue
		}
		if words[0] == "array" {
			p.Arrays = append(p.Arrays, Array{words[1], int(integer(words[2]))})
			continue
		}
		if words[0] == "func" {
			f = &Function{Name: words[1], Parameters: append([]string{}, words[2:]...)}
			p.Functions = append(p.Functions, f)
			continue
		}
		if words[0] == "end" {
			continue
		}
		if len(words) == 1 && strings.HasSuffix(words[0], ":") {
			f.Code = append(f.Code, CodeLine{Label: strings.TrimSuffix(words[0], ":")})
			continue
		}
		s := &Instruction{}
		switch words[0] {
		case "goto":
			s.Kind = "goto"
			s.Name = words[1]
		case "if":
			s.Kind = "if"
			s.A = operand(words[1])
			s.Operator = words[2]
			s.B = operand(words[3])
			s.Name = words[5]
		case "param", "print":
			s.Kind = words[0]
			s.A = operand(words[1])
		case "read":
			s.Kind = "read"
			s.Destination = words[1]
		case "return":
			s.Kind = "return"
			if len(words) == 2 {
				s.HasA = true
				s.A = operand(words[1])
			}
		case "call":
			s.Kind = "call"
			s.Name = words[1]
			s.Count = int(integer(words[2]))
		default:
			if strings.Contains(words[0], "[") {
				s.Kind = "store"
				s.Name, s.A = arrayOperand(words[0])
				s.B = operand(words[2])
			} else {
				s.Destination = words[0]
				if words[2] == "call" {
					s.Kind = "call"
					s.Name = words[3]
					s.Count = int(integer(words[4]))
				} else if len(words) == 5 {
					s.Kind = "bin"
					s.A = operand(words[2])
					s.Operator = words[3]
					s.B = operand(words[4])
				} else if strings.Contains(words[2], "[") {
					s.Kind = "load"
					s.Name, s.A = arrayOperand(words[2])
				} else {
					s.Kind = "copy"
					s.A = operand(words[2])
				}
			}
		}
		f.Code = append(f.Code, CodeLine{Instruction: s})
	}
	return p
}
func functionLines(f *Function) []string {
	header := "func " + f.Name
	for _, parameter := range f.Parameters {
		header += " " + parameter
	}
	out := []string{header}
	for _, line := range f.Code {
		if line.Instruction == nil {
			out = append(out, line.Label+":")
		} else {
			out = append(out, "    "+line.Instruction.String())
		}
	}
	return append(out, "end")
}
func programLines(p *Program) []string {
	out := []string{}
	for _, array := range p.Arrays {
		out = append(out, fmt.Sprintf("array %s %d", array.Name, array.Size))
	}
	for i, f := range p.Functions {
		if i > 0 || len(p.Arrays) > 0 {
			out = append(out, "")
		}
		out = append(out, functionLines(f)...)
	}
	return out
}
func calculate(op string, a, b int64) int64 {
	switch op {
	case "+":
		return a + b
	case "-":
		return a - b
	case "*":
		return a * b
	case "/":
		return a / b
	case "%":
		return a - (a/b)*b
	case "<":
		if a < b {
			return 1
		}
	case "<=":
		if a <= b {
			return 1
		}
	case ">":
		if a > b {
			return 1
		}
	case ">=":
		if a >= b {
			return 1
		}
	case "==":
		if a == b {
			return 1
		}
	case "!=":
		if a != b {
			return 1
		}
	}
	return 0
}
