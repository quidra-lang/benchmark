package main

import "math"

type Model struct {
	Selected     []int
	Coefficients []float64
	Inverse      [][]float64
}

func angle(speed, t float64) float64 {
	d := speed * t
	d2 := d - 360*math.Floor(d/360)
	return d2 * 3.141592653589793 / 180
}
func regressors(t float64, selected []int, c []Constituent) []float64 {
	x := make([]float64, 1+2*len(selected))
	x[0] = 1
	for k, i := range selected {
		a := angle(c[i].Speed, t)
		x[2*k+1], x[2*k+2] = math.Cos(a), math.Sin(a)
	}
	return x
}
func fit(times []int, values map[int]float64, selected []int, c []Constituent) Model {
	p := 1 + 2*len(selected)
	m := make([][]float64,
		p)
	for i := range m {
		m[i] = make([]float64, 2*p+1)
		m[i][p+1+i] = 1
	}
	for _, t := range times {
		x := regressors(float64(t),
			selected, c)
		for i := 0; i < p; i++ {
			for j := 0; j < p; j++ {
				m[i][j] += x[i] * x[j]
			}
			m[i][p] += x[i] * values[t]
		}
	}
	for j := 0; j < p; j++ {
		pivot := j
		for i := j + 1; i < p; i++ {
			if math.Abs(m[i][j]) > math.Abs(m[pivot][j]) {
				pivot = i
			}
		}
		m[j],
			m[pivot] = m[pivot], m[j]
		for i := j + 1; i < p; i++ {
			f := m[i][j] / m[j][j]
			for col := j; col <= 2*p; col++ {
				m[i][col] -= f * m[j][col]
			}
		}
	}
	model := Model{Selected: append([]int(nil),
		selected...), Inverse: make([][]float64, p)}
	for i := 0; i < p; i++ {
		model.Inverse[i] = make([]float64, p)
	}
	for col := p; col <= 2*p; col++ {
		sol := make([]float64,
			p)
		for i := p - 1; i >= 0; i-- {
			s := m[i][col]
			for j := i + 1; j < p; j++ {
				s -= m[i][j] * sol[j]
			}
			sol[i] = s / m[i][i]
		}
		if col == p {
			model.Coefficients = sol
		} else {
			for i := 0; i < p; i++ {
				model.Inverse[i][col-p-1] = sol[i]
			}
		}
	}
	return model
}
func amplitudePhase(a, b float64) (float64, float64) {
	amp := math.Sqrt(a*a + b*b)
	g := math.Atan2(b, a) * 180 / 3.141592653589793
	if g < 0 {
		g += 360
	}
	return amp, g
}
