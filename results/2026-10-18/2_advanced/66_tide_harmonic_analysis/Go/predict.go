package main

import "math"

type Extremum struct {
	Minute     int
	Mu, Height float64
	High       bool
	Label      string
}

func predict(model Model, c []Constituent, t float64) float64 {
	h := model.Coefficients[0]
	for k, i := range model.Selected {
		a := angle(c[i].Speed,
			t)
		h += model.Coefficients[2*k+1]*math.Cos(a) + model.Coefficients[2*k+2]*math.Sin(a)
	}
	return h
}
func extrema(model Model, c []Constituent, p Settings) []Extremum {
	n := p.Hours * 60 / p.Grid
	y := make([]float64,
		n+1)
	for j := 0; j <= n; j++ {
		y[j] = predict(model, c, float64(60*p.Start+j*p.Grid)/60)
	}
	var a []Extremum
	for j := 1; j < n; j++ {
		high := y[j-1] < y[j] && y[j] > y[j+1]
		low := y[j-1] > y[j] && y[j] < y[j+1]
		if high || low {
			delta := (y[j-1] - y[j+1]) / (2 * (y[j-1] - 2*y[j] + y[j+1]))
			mu := float64(60*p.Start+j*p.Grid) + delta*float64(p.Grid)
			height := y[j] - (y[j-1]-y[j+1])*delta/4
			a = append(a,
				Extremum{int(math.Floor(mu + 0.5)), mu, height, high, ""})
		}
	}
	return a
}
