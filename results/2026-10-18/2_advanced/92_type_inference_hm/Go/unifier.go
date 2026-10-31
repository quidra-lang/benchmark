package main

type Type struct {
	Kind     string
	Children []*Type
	Binding  *Type
}
type Scheme struct {
	Type       *Type
	Quantified map[*Type]bool
}
type TypeEnv map[string]Scheme

var intType = &Type{Kind: "int"}
var boolType = &Type{Kind: "bool"}
var stringType = &Type{Kind: "string"}

func fresh() *Type                                     { return &Type{Kind: "var"} }
func constructed(kind string, children ...*Type) *Type { return &Type{Kind: kind, Children: children} }
func resolve(t *Type) *Type {
	if t.Kind == "var" && t.Binding != nil {
		t.Binding = resolve(t.Binding)
		return t.Binding
	}
	return t
}
func occurs(variable, t *Type) bool {
	t = resolve(t)
	if t == variable {
		return true
	}
	for _, child := range t.Children {
		if occurs(variable, child) {
			return true
		}
	}
	return false
}

type UnificationFailure struct {
	Expected, Found  *Type
	Infinite, Nested bool
}

func unify(expected, found *Type, nested bool) *UnificationFailure {
	expected, found = resolve(expected), resolve(found)
	if expected == found {
		return nil
	}
	if expected.Kind == "var" {
		if occurs(expected, found) {
			return &UnificationFailure{expected, found, true, nested}
		}
		expected.Binding = found
		return nil
	}
	if found.Kind == "var" {
		if occurs(found, expected) {
			return &UnificationFailure{expected, found, true, nested}
		}
		found.Binding = expected
		return nil
	}
	if expected.Kind != found.Kind {
		return &UnificationFailure{expected, found, false, nested}
	}
	for i, child := range expected.Children {
		if failure := unify(child, found.Children[i], true); failure != nil {
			return failure
		}
	}
	return nil
}
func freeVariables(t *Type) map[*Type]bool {
	out := map[*Type]bool{}
	var walk func(*Type)
	walk = func(value *Type) {
		value = resolve(value)
		if value.Kind == "var" {
			out[value] = true
			return
		}
		for _, child := range value.Children {
			walk(child)
		}
	}
	walk(t)
	return out
}
func generalize(t *Type, env TypeEnv) Scheme {
	quantified := freeVariables(t)
	for _, scheme := range env {
		for variable := range freeVariables(scheme.Type) {
			if !scheme.Quantified[variable] {
				delete(quantified, variable)
			}
		}
	}
	return Scheme{t, quantified}
}
func instantiate(s Scheme) *Type {
	replacements := map[*Type]*Type{}
	var copy func(*Type) *Type
	copy = func(t *Type) *Type {
		t = resolve(t)
		if t.Kind == "var" {
			if !s.Quantified[t] {
				return t
			}
			if replacements[t] == nil {
				replacements[t] = fresh()
			}
			return replacements[t]
		}
		children := []*Type{}
		for _, child := range t.Children {
			children = append(children, copy(child))
		}
		return constructed(t.Kind, children...)
	}
	return copy(s.Type)
}
func copyTypes(env TypeEnv) TypeEnv {
	out := TypeEnv{}
	for name, scheme := range env {
		out[name] = scheme
	}
	return out
}
