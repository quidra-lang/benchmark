package main

import "sort"

type Factor struct {
	Variables []int
	Values    []float64
}
type Evidence struct{ V, S int }

func assignmentCount(vars []int, n Network) int {
	count := 1
	for _, v := range vars {
		count *= len(n.Variables[v].States)
	}
	return count
}
func assignments(vars []int, n Network, visit func([]int)) {
	a := make([]int, len(n.Variables))
	var walk func(int)
	walk = func(pos int) {
		if pos == len(vars) {
			visit(a)
			return
		}
		v := vars[pos]
		for state := range n.Variables[v].States {
			a[v] = state
			walk(pos + 1)
		}
	}
	walk(0)
}
func variableUnion(lists ...[]int) []int {
	set := map[int]bool{}
	for _, a := range lists {
		for _, v := range a {
			set[v] = true
		}
	}
	var result []int
	for v := range set {
		result = append(result,
			v)
	}
	sort.Ints(result)
	return result
}
func without(vars []int, remove map[int]bool) []int {
	var a []int
	for _, v := range vars {
		if !remove[v] {
			a = append(a, v)
		}
	}
	return a
}
func factorIndex(vars, a []int, n Network) int {
	index := 0
	for _, v := range vars {
		index = index*len(n.Variables[v].States) + a[v]
	}
	return index
}
func (f Factor) value(a []int, n Network) float64 { return f.Values[factorIndex(f.Variables, a, n)] }
func cptFactor(v int, n Network) Factor {
	co := n.Variables[v]
	f := Factor{Variables: variableUnion([]int{v},
		co.Parents)}
	assignments(f.Variables, n, func(a []int) {
		f.Values = append(f.Values, co.Theta[parentCombination(co.Parents,
			a, n)][a[v]])
	})
	return f
}
func reduce(f Factor, e []Evidence, n Network) Factor {
	remove := map[int]bool{}
	for _, ev := range e {
		remove[ev.V] = true
	}
	g := Factor{Variables: without(f.Variables,
		remove)}
	assignments(g.Variables, n, func(a []int) {
		for _, ev := range e {
			a[ev.V] = ev.S
		}
		g.Values = append(g.Values,
			f.value(a, n))
	})
	return g
}
func multiply(a, b Factor, n Network) Factor {
	f := Factor{Variables: variableUnion(a.Variables, b.Variables)}
	assignments(f.Variables,
		n, func(state []int) { f.Values = append(f.Values, a.value(state, n)*b.value(state, n)) })
	return f
}
func product(factors []Factor, n Network) Factor {
	if len(factors) == 0 {
		return Factor{Values: []float64{1}}
	}
	f := factors[0]
	for _, g := range factors[1:] {
		f = multiply(f, g, n)
	}
	return f
}
func eliminate(f Factor, v int, maximum bool, n Network) Factor {
	g := Factor{Variables: without(f.Variables,
		map[int]bool{v: true})}
	assignments(g.Variables, n, func(a []int) {
		value := 0.0
		if maximum {
			value = -1
		}
		for state := range n.Variables[v].States {
			a[v] = state
			x := f.value(a,
				n)
			if maximum {
				if x > value {
					value = x
				}
			} else {
				value += x
			}
		}
		g.Values = append(g.Values, value)
	})
	return g
}
