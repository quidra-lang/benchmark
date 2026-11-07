package main

type TypeError struct {
	Kind, Name string
	Position
	Expected, Found *Type
	Failure         *UnificationFailure
	Candidates      []string
}
type Inferencer struct{ Locals []*Binding }

func (i *Inferencer) check(expected, found *Type, pos Position) {
	if failure := unify(expected, found, false); failure != nil {
		panic(&TypeError{Kind: "check", Position: pos, Expected: expected, Found: found, Failure: failure})
	}
}
func operatorTypes(op string) (*Type, *Type, *Type) {
	if wordIn("+ - * / mod", op) {
		return intType, intType, intType
	}
	if op == "^" {
		return stringType, stringType, stringType
	}
	if op == "&&" || op == "||" {
		return boolType, boolType, boolType
	}
	variable := fresh()
	if op == "::" {
		sequence := constructed("list", variable)
		return variable, sequence, sequence
	}
	return variable, variable, boolType
}
func (i *Inferencer) expression(e *Expr, env TypeEnv) *Type {
	var result *Type
	c := e.Children
	switch e.Kind {
	case "integer":
		result = intType
	case "string":
		result = stringType
	case "boolean":
		result = boolType
	case "name":
		scheme, ok := env[e.Value]
		if !ok {
			names := []string{}
			for name := range env {
				names = append(names, name)
			}
			panic(&TypeError{Kind: "unbound", Name: e.Value, Position: e.Position, Candidates: names})
		}
		result = instantiate(scheme)
	case "fun":
		argument := fresh()
		inner := copyTypes(env)
		if e.Token.Spelling != "_" {
			inner[e.Token.Spelling] = Scheme{Type: argument}
		}
		result = constructed("function", argument, i.expression(c[0], inner))
	case "apply":
		function := resolve(i.expression(c[0], env))
		var argument *Type
		if function.Kind == "var" {
			argument = fresh()
			result = fresh()
			function.Binding = constructed("function", argument, result)
		} else if function.Kind == "function" {
			argument, result = function.Children[0], function.Children[1]
		} else {
			panic(&TypeError{Kind: "not_function", Position: c[0].Position, Found: function})
		}
		found := i.expression(c[1], env)
		i.check(argument, found, c[1].Position)
	case "binary":
		first, second, r := operatorTypes(e.Token.Spelling)
		left := i.expression(c[0], env)
		i.check(first, left, c[0].Position)
		right := i.expression(c[1], env)
		i.check(second, right, c[1].Position)
		result = r
	case "negate":
		found := i.expression(c[0], env)
		i.check(intType, found, c[0].Position)
		result = intType
	case "if":
		condition := i.expression(c[0], env)
		i.check(boolType, condition, c[0].Position)
		result = i.expression(c[1], env)
		other := i.expression(c[2], env)
		i.check(result, other, c[2].Position)
	case "pair":
		first := i.expression(c[0], env)
		second := i.expression(c[1], env)
		result = constructed("pair", first, second)
	case "list":
		element := fresh()
		for _, child := range c {
			found := i.expression(child, env)
			i.check(element, found, child.Position)
		}
		result = constructed("list", element)
	case "match":
		matched := i.expression(c[0], env)
		result = fresh()
		for _, arm := range e.Arms {
			bindings := map[string]*Type{}
			patternType := i.pattern(arm.Pattern, bindings)
			i.check(matched, patternType, arm.Pattern.Position)
			inner := copyTypes(env)
			for name, t := range bindings {
				inner[name] = Scheme{Type: t}
			}
			found := i.expression(arm.Body, inner)
			i.check(result, found, arm.Body.Position)
		}
	case "let":
		inner := i.group(e.Group, env, true)
		result = i.expression(c[0], inner)
	}
	e.Inferred = result
	return result
}
func (i *Inferencer) pattern(p *Expr, bindings map[string]*Type) *Type {
	c := p.Children
	switch p.Kind {
	case "wildcard":
		return fresh()
	case "name":
		if _, ok := bindings[p.Value]; ok {
			panic(&TypeError{Kind: "duplicate_pattern", Name: p.Value, Position: p.Position})
		}
		t := fresh()
		bindings[p.Value] = t
		return t
	case "integer":
		return intType
	case "boolean":
		return boolType
	case "string":
		return stringType
	case "pair":
		first := i.pattern(c[0], bindings)
		second := i.pattern(c[1], bindings)
		return constructed("pair", first, second)
	}
	element := fresh()
	sequence := constructed("list", element)
	if p.Kind == "cons" {
		first := i.pattern(c[0], bindings)
		i.check(element, first, c[0].Position)
		second := i.pattern(c[1], bindings)
		i.check(sequence, second, c[1].Position)
	} else {
		for _, child := range c {
			found := i.pattern(child, bindings)
			i.check(element, found, child.Position)
		}
	}
	return sequence
}
func (i *Inferencer) group(g *Group, env TypeEnv, local bool) TypeEnv {
	seen := map[string]bool{}
	for _, binding := range g.Bindings {
		name := binding.Name.Spelling
		if seen[name] {
			panic(&TypeError{Kind: "duplicate_let", Name: name, Position: binding.Name.Position})
		}
		seen[name] = true
		if g.Rec != nil && binding.Expr.Kind != "fun" {
			panic(&TypeError{Kind: "recursive_function", Name: name, Position: binding.Name.Position})
		}
	}
	types := make([]*Type, len(g.Bindings))
	if g.Rec == nil {
		for j, binding := range g.Bindings {
			types[j] = i.expression(binding.Expr, env)
		}
	} else {
		recursive := copyTypes(env)
		for j, binding := range g.Bindings {
			types[j] = fresh()
			recursive[binding.Name.Spelling] = Scheme{Type: types[j]}
		}
		for j, binding := range g.Bindings {
			found := i.expression(binding.Expr, recursive)
			i.check(types[j], found, binding.Name.Position)
		}
	}
	result := copyTypes(env)
	for j, binding := range g.Bindings {
		binding.Scheme = generalize(types[j], env)
		result[binding.Name.Spelling] = binding.Scheme
	}
	if local {
		i.Locals = append(i.Locals, g.Bindings...)
	}
	return result
}
