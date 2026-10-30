package main

import (
	"regexp"
	"strconv"
	"strings"
)

type ExpressionError struct{ Message string }
type ConditionExpr struct {
	Kind, Op, Name string
	Value          int64
	Children       []*ConditionExpr
}

var hexPattern = regexp.MustCompile(`^0[xX][0-9a-fA-F]+$`)
var octalPattern = regexp.MustCompile(`^0[0-7]*$`)
var decimalPattern = regexp.MustCompile(`^[1-9][0-9]*$`)

func integerConstant(spelling string) (int64, string) {
	text := spelling
	for _, suffix := range []string{"ll", "LL", "l", "L"} {
		if len(text) > len(suffix) && strings.HasSuffix(text, suffix) {
			text = strings.TrimSuffix(text, suffix)
			break
		}
	}
	base := 0
	if hexPattern.MatchString(text) {
		base = 16
		text = text[2:]
	} else if octalPattern.MatchString(text) {
		base = 8
	} else if decimalPattern.MatchString(text) {
		base = 10
	}
	if base == 0 {
		return 0, `invalid integer constant "` + spelling + `"`
	}
	value, _ := strconv.ParseInt(text, base, 64)
	return value, ""
}
func characterConstant(spelling string) (int64, string) {
	body := spelling[1 : len(spelling)-1]
	if len(body) == 1 && body[0] != '\'' && body[0] != '\\' {
		return int64(body[0]), ""
	}
	if len(body) == 2 && body[0] == '\\' {
		values := map[byte]int64{'n': 10, 't': 9, '\\': 92, '\'': 39, '"': 34, '0': 0}
		if value, ok := values[body[1]]; ok {
			return value, ""
		}
	}
	return 0, "invalid character constant " + spelling
}
func conditionPrecedence(op string) int {
	switch op {
	case "||":
		return 1
	case "&&":
		return 2
	case "|":
		return 3
	case "^":
		return 4
	case "&":
		return 5
	case "==", "!=":
		return 6
	case "<", ">", "<=", ">=":
		return 7
	case "<<", ">>":
		return 8
	case "+", "-":
		return 9
	case "*", "/", "%":
		return 10
	}
	return 0
}

type ExpressionParser struct {
	Tokens []Token
	Index  int
}

func (p *ExpressionParser) peek() string {
	if p.Index == len(p.Tokens) {
		return ""
	}
	return p.Tokens[p.Index].Spelling
}
func expressionError(message string) { panic(&ExpressionError{message}) }
func (p *ExpressionParser) expression() *ConditionExpr {
	first := p.binary(1)
	if p.peek() == "?" {
		p.Index++
		second := p.expression()
		if p.peek() != ":" {
			expressionError("'?' without following ':'")
		}
		p.Index++
		third := p.expression()
		return &ConditionExpr{Kind: "conditional", Children: []*ConditionExpr{first, second, third}}
	}
	return first
}
func (p *ExpressionParser) binary(minimum int) *ConditionExpr {
	left := p.unary()
	for {
		level := conditionPrecedence(p.peek())
		if level == 0 || level < minimum {
			break
		}
		op := p.peek()
		p.Index++
		right := p.binary(level + 1)
		left = &ConditionExpr{Kind: "binary", Op: op, Children: []*ConditionExpr{left, right}}
	}
	return left
}
func (p *ExpressionParser) unary() *ConditionExpr {
	if wordIn("+ - ! ~", p.peek()) {
		op := p.peek()
		p.Index++
		return &ConditionExpr{Kind: "unary", Op: op, Children: []*ConditionExpr{p.unary()}}
	}
	return p.primary()
}
func (p *ExpressionParser) primary() *ConditionExpr {
	if p.Index == len(p.Tokens) {
		expressionError("expected value at end of expression")
	}
	token := p.Tokens[p.Index]
	p.Index++
	switch token.Kind {
	case "number", "character":
		value, error := int64(0), ""
		if token.Kind == "number" {
			value, error = integerConstant(token.Spelling)
		} else {
			value, error = characterConstant(token.Spelling)
		}
		if error != "" {
			expressionError(error)
		}
		return &ConditionExpr{Kind: "constant", Value: value}
	case "identifier":
		return &ConditionExpr{Kind: "identifier", Name: token.Spelling}
	}
	if token.Spelling == "(" {
		e := p.expression()
		if p.peek() != ")" {
			expressionError("missing ')' in expression")
		}
		p.Index++
		return e
	}
	expressionError(`expected value before "` + token.Spelling + `"`)
	return nil
}
func parseCondition(tokens []Token, directive string) (tree *ConditionExpr, err *ExpressionError) {
	defer func() {
		if value := recover(); value != nil {
			if failure, ok := value.(*ExpressionError); ok {
				err = failure
			} else {
				panic(value)
			}
		}
	}()
	if len(tokens) == 0 {
		expressionError("#" + directive + " with no expression")
	}
	p := ExpressionParser{Tokens: tokens}
	tree = p.expression()
	if p.Index < len(tokens) {
		expressionError(`missing binary operator before "` + p.peek() + `"`)
	}
	return
}
func evaluateCondition(e *ConditionExpr, warning func(string)) (value int64, err *ExpressionError) {
	defer func() {
		if v := recover(); v != nil {
			if failure, ok := v.(*ExpressionError); ok {
				err = failure
			} else {
				panic(v)
			}
		}
	}()
	value = evalCondition(e, warning)
	return
}
func evalCondition(e *ConditionExpr, warning func(string)) int64 {
	switch e.Kind {
	case "constant":
		return e.Value
	case "identifier":
		warning(`identifier "` + e.Name + `" evaluates to 0`)
		return 0
	case "unary":
		a := evalCondition(e.Children[0], warning)
		switch e.Op {
		case "+":
			return a
		case "-":
			return -a
		case "!":
			if a == 0 {
				return 1
			}
			return 0
		case "~":
			return -a - 1
		}
	case "conditional":
		condition := evalCondition(e.Children[0], warning)
		if condition != 0 {
			return evalCondition(e.Children[1], warning)
		}
		return evalCondition(e.Children[2], warning)
	case "binary":
		a := evalCondition(e.Children[0], warning)
		if e.Op == "&&" && a == 0 {
			return 0
		}
		if e.Op == "||" && a != 0 {
			return 1
		}
		b := evalCondition(e.Children[1], warning)
		answer := false
		switch e.Op {
		case "+":
			return a + b
		case "-":
			return a - b
		case "*":
			return a * b
		case "/", "%":
			if b == 0 {
				expressionError("division by zero in #if")
			}
			q := a / b
			if e.Op == "/" {
				return q
			}
			return a - b*q
		case "<<":
			return a << uint(b)
		case ">>":
			return a >> uint(b)
		case "&":
			return a & b
		case "|":
			return a | b
		case "^":
			return a ^ b
		case "==":
			answer = a == b
		case "!=":
			answer = a != b
		case "<":
			answer = a < b
		case "<=":
			answer = a <= b
		case ">":
			answer = a > b
		case ">=":
			answer = a >= b
		case "&&", "||":
			answer = b != 0
		}
		if answer {
			return 1
		}
		return 0
	}
	return 0
}
