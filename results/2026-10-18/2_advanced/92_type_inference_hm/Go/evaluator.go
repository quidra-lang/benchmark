package main

import "strconv"

type Value struct {
	Kind, Text, Builtin string
	Integer             int64
	Boolean             bool
	Items               []*Value
	Parameter           Token
	Body                *Expr
	Env                 ValueEnv
}
type ValueEnv map[string]*Value
type RuntimeError struct {
	Position
	Message string
}
type Evaluator struct{ Calls int }

func intValue(v int64) *Value     { return &Value{Kind: "integer", Integer: v} }
func boolValue(v bool) *Value     { return &Value{Kind: "boolean", Boolean: v} }
func stringValue(v string) *Value { return &Value{Kind: "string", Text: v} }
func copyValues(env ValueEnv) ValueEnv {
	out := ValueEnv{}
	for name, value := range env {
		out[name] = value
	}
	return out
}
func checked(v int64, pos Position) *Value {
	if v < -2147483648 || v > 2147483647 {
		panic(&RuntimeError{pos, "integer overflow"})
	}
	return intValue(v)
}
func compareValues(a, b *Value, pos Position) int {
	switch a.Kind {
	case "integer":
		if a.Integer < b.Integer {
			return -1
		}
		if a.Integer > b.Integer {
			return 1
		}
		return 0
	case "boolean":
		if a.Boolean == b.Boolean {
			return 0
		}
		if a.Boolean {
			return 1
		}
		return -1
	case "string":
		if a.Text < b.Text {
			return -1
		}
		if a.Text > b.Text {
			return 1
		}
		return 0
	case "function":
		panic(&RuntimeError{pos, "functional value compared"})
	case "pair", "list":
		for j := 0; j < len(a.Items) && j < len(b.Items); j++ {
			if c := compareValues(a.Items[j], b.Items[j], pos); c != 0 {
				return c
			}
		}
		if len(a.Items) < len(b.Items) {
			return -1
		}
		if len(a.Items) > len(b.Items) {
			return 1
		}
	}
	return 0
}
func matchPattern(p *Expr, v *Value, bindings ValueEnv) bool {
	switch p.Kind {
	case "wildcard":
		return true
	case "name":
		bindings[p.Value] = v
		return true
	case "integer":
		return p.Integer == v.Integer
	case "string":
		return p.Value == v.Text
	case "boolean":
		return (p.Value == "true") == v.Boolean
	case "pair":
		return matchPattern(p.Children[0], v.Items[0], bindings) && matchPattern(p.Children[1], v.Items[1], bindings)
	case "list":
		if len(p.Children) != len(v.Items) {
			return false
		}
		for j, child := range p.Children {
			if !matchPattern(child, v.Items[j], bindings) {
				return false
			}
		}
		return true
	case "cons":
		return len(v.Items) > 0 && matchPattern(p.Children[0], v.Items[0], bindings) && matchPattern(p.Children[1], &Value{Kind: "list", Items: v.Items[1:]}, bindings)
	}
	return false
}
func (v *Evaluator) apply(f, a *Value, pos Position) *Value {
	v.Calls++
	if f.Builtin != "" {
		switch f.Builtin {
		case "fst":
			return a.Items[0]
		case "snd":
			return a.Items[1]
		case "not":
			return boolValue(!a.Boolean)
		case "string_of_int":
			return stringValue(strconv.FormatInt(a.Integer, 10))
		case "failwith":
			panic(&RuntimeError{pos, "failure " + printValue(a)})
		}
	}
	inner := copyValues(f.Env)
	if f.Parameter.Spelling != "_" {
		inner[f.Parameter.Spelling] = a
	}
	return v.expression(f.Body, inner)
}
func (v *Evaluator) expression(e *Expr, env ValueEnv) *Value {
	c := e.Children
	switch e.Kind {
	case "integer":
		return intValue(e.Integer)
	case "boolean":
		return boolValue(e.Value == "true")
	case "string":
		return stringValue(e.Value)
	case "name":
		return env[e.Value]
	case "fun":
		return &Value{Kind: "function", Parameter: e.Token, Body: c[0], Env: env}
	case "apply":
		function := v.expression(c[0], env)
		argument := v.expression(c[1], env)
		return v.apply(function, argument, e.Position)
	case "negate":
		value := v.expression(c[0], env)
		return checked(-value.Integer, e.Token.Position)
	case "if":
		condition := v.expression(c[0], env)
		if condition.Boolean {
			return v.expression(c[1], env)
		}
		return v.expression(c[2], env)
	case "pair", "list":
		values := []*Value{}
		for _, child := range c {
			values = append(values, v.expression(child, env))
		}
		return &Value{Kind: e.Kind, Items: values}
	case "let":
		inner, _ := v.group(e.Group, env)
		return v.expression(c[0], inner)
	case "match":
		value := v.expression(c[0], env)
		for _, arm := range e.Arms {
			bindings := ValueEnv{}
			if matchPattern(arm.Pattern, value, bindings) {
				inner := copyValues(env)
				for name, matched := range bindings {
					inner[name] = matched
				}
				return v.expression(arm.Body, inner)
			}
		}
		panic(&RuntimeError{e.Position, "match failure"})
	case "binary":
		left := v.expression(c[0], env)
		op := e.Token.Spelling
		if op == "&&" && !left.Boolean {
			return boolValue(false)
		}
		if op == "||" && left.Boolean {
			return boolValue(true)
		}
		right := v.expression(c[1], env)
		pos := e.Token.Position
		switch op {
		case "&&", "||":
			return right
		case "+":
			return checked(left.Integer+right.Integer, pos)
		case "-":
			return checked(left.Integer-right.Integer, pos)
		case "*":
			return checked(left.Integer*right.Integer, pos)
		case "/", "mod":
			if right.Integer == 0 {
				panic(&RuntimeError{pos, "division by zero"})
			}
			quotient := left.Integer / right.Integer
			if op == "/" {
				return checked(quotient, pos)
			}
			return intValue(left.Integer - right.Integer*quotient)
		case "^":
			return stringValue(left.Text + right.Text)
		case "::":
			items := append([]*Value{left}, right.Items...)
			return &Value{Kind: "list", Items: items}
		default:
			comparison := compareValues(left, right, pos)
			answer := false
			switch op {
			case "=":
				answer = comparison == 0
			case "<>":
				answer = comparison != 0
			case "<":
				answer = comparison < 0
			case ">":
				answer = comparison > 0
			case "<=":
				answer = comparison <= 0
			case ">=":
				answer = comparison >= 0
			}
			return boolValue(answer)
		}
	}
	return nil
}
func (v *Evaluator) group(g *Group, env ValueEnv) (ValueEnv, []*Value) {
	inner := copyValues(env)
	values := make([]*Value, len(g.Bindings))
	if g.Rec == nil {
		for j, binding := range g.Bindings {
			values[j] = v.expression(binding.Expr, env)
		}
		for j, binding := range g.Bindings {
			inner[binding.Name.Spelling] = values[j]
		}
	} else {
		for j, binding := range g.Bindings {
			e := binding.Expr
			values[j] = &Value{Kind: "function", Parameter: e.Token, Body: e.Children[0], Env: inner}
			inner[binding.Name.Spelling] = values[j]
		}
	}
	return inner, values
}
