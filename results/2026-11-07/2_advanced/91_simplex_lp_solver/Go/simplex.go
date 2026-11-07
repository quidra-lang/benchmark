package main

import "fmt"

type PhaseResult struct {
	Iterations, Entering int
	Lines                []string
}

func phase(tableau *Tableau, cost []Fraction, candidates []bool, columns, rows []string, objective func(Fraction) Fraction) PhaseResult {
	result := PhaseResult{Entering: -1}
	for {
		reduced, _ := tableau.reduced(cost)
		q := -1
		for k, value := range reduced {
			if candidates[k] && value.N < 0 {
				q = k
				break
			}
		}
		if q < 0 {
			return result
		}
		p := -1
		ratio := integer(0)
		for i, row := range tableau.T {
			if row[q].N <= 0 {
				continue
			}
			value := tableau.Beta[i].div(row[q])
			if p < 0 || value.cmp(ratio) < 0 || value.cmp(ratio) == 0 && tableau.Basis[i] < tableau.Basis[p] {
				p = i
				ratio = value
			}
		}
		if p < 0 {
			result.Entering = q
			return result
		}
		leave := tableau.Basis[p]
		before := reduced[q]
		tableau.pivot(p, q)
		result.Iterations++
		_, z := tableau.reduced(cost)
		result.Lines = append(result.Lines, fmt.Sprintf("PIVOT %d enter %s reduced %s leave %s row %s ratio %s objective %s", result.Iterations, columns[q], before, columns[leave], rows[p], ratio, objective(z)))
	}
}
