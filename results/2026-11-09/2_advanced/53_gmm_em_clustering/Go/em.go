package main

import "math"

func adjustType(initial Model, kind string) Model {
	model := append(Model{}, initial...)
	shared := Covariance{}
	if kind == "TIED" {
		for _, c := range model {
			shared.A += c.Weight * c.Cov.A
			shared.B += c.Weight * c.Cov.B
			shared.C += c.Weight * c.Cov.C
		}
	}
	for i, c := range model {
		switch kind {
		case "DIAG":
			model[i].Cov = Covariance{c.Cov.A, 0, c.Cov.C}
		case "SPHERICAL":
			v := (c.Cov.A + c.Cov.C) / 2
			model[i].Cov = Covariance{v, 0, v}
		case "TIED":
			model[i].Cov = shared
		}
	}
	return model
}

type ERecord struct {
	Responsibilities, Scores []float64
	LogDensity               float64
}

func expectation(points []DataPoint, model Model) ([]ERecord, float64) {
	records := make([]ERecord, len(points))
	loglik := 0.0
	for i, point := range points {
		scores := make([]float64, len(model))
		maximum := math.Inf(-1)
		for k, c := range model {
			scores[k] = weightedLogDensity(point.Point, c)
			maximum = math.Max(maximum, scores[k])
		}
		exponentials := make([]float64, len(model))
		total := 0.0
		for k, score := range scores {
			exponentials[k] = math.Exp(score - maximum)
			total += exponentials[k]
		}
		for k := range exponentials {
			exponentials[k] /= total
		}
		density := maximum + math.Log(total)
		records[i] = ERecord{exponentials, scores, density}
		loglik += density
	}
	return records, loglik
}
func maximization(points []DataPoint, records []ERecord, kind string, epsilon float64) Model {
	n, kCount := len(points), len(records[0].Responsibilities)
	model := make(Model, kCount)
	counts := make([]float64, kCount)
	scatter := make([]Covariance, kCount)
	for k := 0; k < kCount; k++ {
		count, x, y := 0.0, 0.0, 0.0
		for i, point := range points {
			r := records[i].Responsibilities[k]
			count += r
			x += r * point.Point.X
			y += r * point.Point.Y
		}
		counts[k] = count
		model[k] = Component{Weight: count / float64(n), Mean: Point{x / count, y / count}}
		a, b, c := 0.0, 0.0, 0.0
		for i, point := range points {
			r := records[i].Responsibilities[k]
			dx, dy := point.Point.X-model[k].Mean.X, point.Point.Y-model[k].Mean.Y
			a += r * dx * dx
			b += r * dx * dy
			c += r * dy * dy
		}
		scatter[k] = Covariance{a, b, c}
	}
	if kind == "TIED" {
		a, b, c := 0.0, 0.0, 0.0
		for _, s := range scatter {
			a += s.A
			b += s.B
			c += s.C
		}
		shared := Covariance{a/float64(n) + epsilon, b / float64(n), c/float64(n) + epsilon}
		for k := range model {
			model[k].Cov = shared
		}
	} else {
		for k, s := range scatter {
			count := counts[k]
			switch kind {
			case "FULL":
				model[k].Cov = Covariance{s.A/count + epsilon, s.B / count, s.C/count + epsilon}
			case "DIAG":
				model[k].Cov = Covariance{s.A/count + epsilon, 0, s.C/count + epsilon}
			case "SPHERICAL":
				v := (s.A/count+s.C/count)/2 + epsilon
				model[k].Cov = Covariance{v, 0, v}
			}
		}
	}
	return model
}

type EMRun struct {
	Model                       Model
	Records                     []ERecord
	Trace                       []float64
	Loglik                      float64
	SettledAt, LargestIteration int
	LargestIncrease             float64
	Violations                  []int
}

func runEM(points []DataPoint, initial Model, kind string, p Params) EMRun {
	model := adjustType(initial, kind)
	records, loglik := expectation(points, model)
	trace := []float64{loglik}
	for t := 0; t < p.Iterations; t++ {
		model = maximization(points, records, kind, p.Epsilon)
		records, loglik = expectation(points, model)
		trace = append(trace, loglik)
	}
	out := EMRun{Model: model, Records: records, Trace: trace, Loglik: loglik, LargestIteration: 1, LargestIncrease: trace[1] - trace[0]}
	out.SettledAt = len(trace) - 1
	for t := len(trace) - 1; t >= 0; t-- {
		if math.Abs(trace[t]-loglik) > p.Tolerance {
			break
		}
		out.SettledAt = t
	}
	for t := 1; t < len(trace); t++ {
		increase := trace[t] - trace[t-1]
		if increase > out.LargestIncrease {
			out.LargestIncrease = increase
			out.LargestIteration = t
		}
		if trace[t] < trace[t-1]-0.000001*math.Abs(trace[t-1]) {
			out.Violations = append(out.Violations, t)
		}
	}
	return out
}
