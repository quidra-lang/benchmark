package main

import "strings"

type BuiltinIssue struct{ Term *Term }

func predicateError(t *Term) { panic(BuiltinIssue{t}) }
func integerCheck(t *Term) int64 {
	t = dereference(t)
	if t.Kind == "variable" {
		predicateError(atom("instantiation_error"))
	}
	if t.Kind != "integer" {
		predicateError(errorTerm("type_error", atom("integer"), t))
	}
	return t.Integer
}
func atomCheck(t *Term) string {
	t = dereference(t)
	if t.Kind == "variable" {
		predicateError(atom("instantiation_error"))
	}
	if t.Kind != "atom" {
		predicateError(errorTerm("type_error", atom("atom"), t))
	}
	return t.Name
}
func properListCheck(t *Term) []*Term {
	elements, tail := listParts(t)
	if tail.Kind == "variable" {
		predicateError(atom("instantiation_error"))
	}
	if !isNil(tail) {
		predicateError(errorTerm("type_error", atom("list"), t))
	}
	return elements
}
func arithmeticValue(t *Term) int64 {
	t = dereference(t)
	if t.Kind == "variable" {
		predicateError(atom("instantiation_error"))
	}
	if t.Kind == "integer" {
		return t.Integer
	}
	p := indicator(t)
	valid := p.Arity == 2 && (p.Name == "+" || p.Name == "-" || p.Name == "*" || p.Name == "//" || p.Name == "mod" || p.Name == "rem" || p.Name == "min" || p.Name == "max") || p.Arity == 1 && (p.Name == "-" || p.Name == "abs")
	if !valid {
		predicateError(errorTerm("type_error", atom("evaluable"), indicatorTerm(p)))
	}
	a := arithmeticValue(t.Arguments[0])
	result := int64(0)
	if p.Arity == 1 {
		result = -a
		if p.Name == "abs" && a >= 0 {
			result = a
		}
	} else {
		b := arithmeticValue(t.Arguments[1])
		switch p.Name {
		case "+":
			result = a + b
		case "-":
			result = a - b
		case "*":
			result = a * b
		case "//", "mod", "rem":
			if b == 0 {
				predicateError(errorTerm("evaluation_error", atom("zero_divisor")))
			}
			q := a / b
			if p.Name == "//" {
				result = q
			} else {
				if p.Name == "mod" && a%b != 0 && (a < 0) != (b < 0) {
					q--
				}
				result = a - b*q
			}
		case "min":
			result = min(a, b)
		case "max":
			result = max(a, b)
		}
	}
	if result < -2147483648 || result > 2147483647 {
		predicateError(errorTerm("evaluation_error", atom("int_overflow")))
	}
	return result
}

var deterministicIndicators = map[Indicator]bool{
	{"true", 0}: true, {"fail", 0}: true, {"false", 0}: true, {"=", 2}: true, {"\\=", 2}: true, {"==", 2}: true, {"\\==", 2}: true,
	{"var", 1}: true, {"nonvar", 1}: true, {"atom", 1}: true, {"number", 1}: true, {"integer", 1}: true, {"atomic", 1}: true, {"compound", 1}: true, {"callable", 1}: true, {"is_list", 1}: true,
	{"is", 2}: true, {"=:=", 2}: true, {"=\\=", 2}: true, {"<", 2}: true, {">", 2}: true, {"=<", 2}: true, {">=", 2}: true,
	{"functor", 3}: true, {"arg", 3}: true, {"=..", 2}: true, {"copy_term", 2}: true, {"atom_length", 2}: true, {"atom_chars", 2}: true, {"write", 1}: true, {"writeq", 1}: true, {"nl", 0}: true,
}

func deterministic(goal *Term, bindings *Bindings, output *strings.Builder) bool {
	p := indicator(goal)
	args := goal.Arguments
	a := func(i int) *Term { return dereference(args[i]) }
	switch p.Name {
	case "true":
		return true
	case "fail", "false":
		return false
	case "=":
		return bindings.unify(args[0], args[1])
	case "\\=":
		mark := bindings.mark()
		success := bindings.unify(args[0], args[1])
		bindings.undo(mark)
		return !success
	case "==":
		return identical(args[0], args[1])
	case "\\==":
		return !identical(args[0], args[1])
	case "var":
		return a(0).Kind == "variable"
	case "nonvar":
		return a(0).Kind != "variable"
	case "atom":
		return a(0).Kind == "atom"
	case "number", "integer":
		return a(0).Kind == "integer"
	case "atomic":
		return a(0).Kind == "atom" || a(0).Kind == "integer"
	case "compound":
		return a(0).Kind == "compound"
	case "callable":
		return a(0).Kind == "atom" || a(0).Kind == "compound"
	case "is_list":
		_, tail := listParts(args[0])
		return isNil(tail)
	case "is":
		value := arithmeticValue(args[1])
		return bindings.unify(args[0], integer(value))
	case "=:=", "=\\=", "<", ">", "=<", ">=":
		x := arithmeticValue(args[0])
		y := arithmeticValue(args[1])
		switch p.Name {
		case "=:=":
			return x == y
		case "=\\=":
			return x != y
		case "<":
			return x < y
		case ">":
			return x > y
		case "=<":
			return x <= y
		case ">=":
			return x >= y
		}
	case "functor":
		t, n, arity := a(0), a(1), a(2)
		if t.Kind != "variable" {
			if t.Kind == "compound" {
				return bindings.unify(args[1], atom(t.Name)) && bindings.unify(args[2], integer(int64(len(t.Arguments))))
			}
			return bindings.unify(args[1], t) && bindings.unify(args[2], integer(0))
		}
		if n.Kind == "variable" || arity.Kind == "variable" {
			predicateError(atom("instantiation_error"))
		}
		if n.Kind == "compound" {
			predicateError(errorTerm("type_error", atom("atomic"), n))
		}
		if arity.Kind != "integer" {
			predicateError(errorTerm("type_error", atom("integer"), arity))
		}
		if arity.Integer < 0 {
			predicateError(errorTerm("domain_error", atom("not_less_than_zero"), arity))
		}
		if arity.Integer > 255 {
			predicateError(errorTerm("representation_error", atom("max_arity")))
		}
		if arity.Integer == 0 {
			return bindings.unify(args[0], n)
		}
		if n.Kind == "integer" {
			predicateError(errorTerm("type_error", atom("atom"), n))
		}
		values := []*Term{}
		for i := int64(0); i < arity.Integer; i++ {
			values = append(values, variable())
		}
		return bindings.unify(args[0], compound(n.Name, values...))
	case "arg":
		n, t := a(0), a(1)
		if n.Kind == "variable" || t.Kind == "variable" {
			predicateError(atom("instantiation_error"))
		}
		if n.Kind != "integer" {
			predicateError(errorTerm("type_error", atom("integer"), n))
		}
		if t.Kind != "compound" {
			predicateError(errorTerm("type_error", atom("compound"), t))
		}
		if n.Integer < 1 || n.Integer > int64(len(t.Arguments)) {
			return false
		}
		return bindings.unify(t.Arguments[int(n.Integer)-1], args[2])
	case "=..":
		t := a(0)
		if t.Kind == "compound" {
			values := append([]*Term{atom(t.Name)}, t.Arguments...)
			return bindings.unify(makeList(values, nil), args[1])
		}
		if t.Kind != "variable" {
			return bindings.unify(makeList([]*Term{t}, nil), args[1])
		}
		elements := properListCheck(args[1])
		if len(elements) == 0 {
			predicateError(errorTerm("domain_error", atom("non_empty_list"), atom("[]")))
		}
		head := dereference(elements[0])
		if head.Kind == "variable" {
			predicateError(atom("instantiation_error"))
		}
		if len(elements) == 1 {
			if head.Kind == "compound" {
				predicateError(errorTerm("type_error", atom("atomic"), head))
			}
			return bindings.unify(args[0], head)
		}
		if head.Kind != "atom" {
			predicateError(errorTerm("type_error", atom("atom"), head))
		}
		if len(elements)-1 > 255 {
			predicateError(errorTerm("representation_error", atom("max_arity")))
		}
		return bindings.unify(args[0], compound(head.Name, elements[1:]...))
	case "copy_term":
		return bindings.unify(copyTerm(args[0]), args[1])
	case "atom_length":
		name := atomCheck(args[0])
		n := a(1)
		if n.Kind != "variable" && n.Kind != "integer" {
			predicateError(errorTerm("type_error", atom("integer"), n))
		}
		return bindings.unify(integer(int64(len(name))), args[1])
	case "atom_chars":
		t := a(0)
		if t.Kind != "variable" {
			name := atomCheck(t)
			values := []*Term{}
			for i := 0; i < len(name); i++ {
				values = append(values, atom(name[i:i+1]))
			}
			return bindings.unify(args[1], makeList(values, nil))
		}
		elements := properListCheck(args[1])
		var name strings.Builder
		for _, element := range elements {
			element = dereference(element)
			if element.Kind == "variable" {
				predicateError(atom("instantiation_error"))
			}
			if element.Kind != "atom" || len(element.Name) != 1 {
				predicateError(errorTerm("type_error", atom("character"), element))
			}
			name.WriteString(element.Name)
		}
		return bindings.unify(args[0], atom(name.String()))
	case "write", "writeq":
		writer := newWriter(p.Name == "writeq")
		output.WriteString(writer.write(args[0], 1200, false))
		return true
	case "nl":
		output.WriteByte('\n')
		return true
	}
	panic("unknown deterministic predicate")
}
