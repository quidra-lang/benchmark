package main

import (
	"fmt"
	"strings"
)

type Tableau struct {
	T     [][]Fraction
	Beta  []Fraction
	Basis []int
}

func (t *Tableau) reduced(cost []Fraction) ([]Fraction, Fraction) {
	r := append([]Fraction{}, cost...)
	z := integer(0)
	for i, basic := range t.Basis {
		z = z.add(cost[basic].mul(t.Beta[i]))
		for k := range r {
			r[k] = r[k].sub(cost[basic].mul(t.T[i][k]))
		}
	}
	return r, z
}
func (t *Tableau) pivot(p, q int) {
	factor := t.T[p][q]
	for k := range t.T[p] {
		t.T[p][k] = t.T[p][k].div(factor)
	}
	t.Beta[p] = t.Beta[p].div(factor)
	for i := range t.T {
		if i == p {
			continue
		}
		f := t.T[i][q]
		for k := range t.T[i] {
			t.T[i][k] = t.T[i][k].sub(f.mul(t.T[p][k]))
		}
		t.Beta[i] = t.Beta[i].sub(f.mul(t.Beta[p]))
	}
	t.Basis[p] = q
}
func (t *Tableau) display(heading string, columns, rows []string, cost []Fraction, constant Fraction, sign int) []string {
	out := []string{"TABLEAU " + heading, "COLUMNS " + strings.Join(columns, " ")}
	for i, row := range t.T {
		values := []string{}
		for _, value := range row {
			values = append(values, value.String())
		}
		out = append(out, fmt.Sprintf("ROW %s %s %s | %s", rows[i], columns[t.Basis[i]], strings.Join(values, " "), t.Beta[i]))
	}
	reduced, z := t.reduced(cost)
	values := []string{}
	for _, value := range reduced {
		values = append(values, value.String())
	}
	out = append(out, fmt.Sprintf("COST %s | %s", strings.Join(values, " "), constant.add(integer(int64(sign)).mul(z))))
	return out
}
