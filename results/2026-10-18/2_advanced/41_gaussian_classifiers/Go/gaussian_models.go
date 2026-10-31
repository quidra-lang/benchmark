package main

import "math"

var modelNames = []string{"NB", "LDA", "QDA"}

type Statistics struct {
	N, P              int
	Counts            []int
	Means             [][]float64
	Scatter           [][][]float64
	Center, Variances []float64
}

func statistics(rows []Row, features []int, c int) *Statistics {
	p := len(features)
	s := &Statistics{N: len(rows), P: p, Counts: make([]int, c), Means: make([][]float64, c), Scatter: make([][][]float64,
		c), Center: make([]float64, p), Variances: make([]float64, p)}
	groups := make([][][]float64, c)
	vectors := [][]float64{}
	for _, r := range rows {
		x := make([]float64, p)
		for j, f := range features {
			x[j] = r.Values[f]
		}
		vectors = append(vectors, x)
		groups[r.Class] = append(groups[r.Class], x)
	}
	for k, group := range groups {
		s.Counts[k] = len(group)
		s.Means[k] = make([]float64, p)
		for j := 0; j < p; j++ {
			t := 0.0
			for _, x := range group {
				t += x[j]
			}
			s.Means[k][j] = t / float64(len(group))
		}
		s.Scatter[k] = zeros(p)
		for a := 0; a < p; a++ {
			for b := 0; b < p; b++ {
				t := 0.0
				for _, x := range group {
					t += (x[a] - s.Means[k][a]) * (x[b] - s.Means[k][b])
				}
				s.Scatter[k][a][b] = t
			}
		}
	}
	for j := 0; j < p; j++ {
		t := 0.0
		for _, x := range vectors {
			t += x[j]
		}
		s.Center[j] = t / float64(s.N)
		t = 0
		for _, x := range vectors {
			t += (x[j] - s.Center[j]) * (x[j] - s.Center[j])
		}
		s.Variances[j] = t / float64(s.N)
	}
	return s
}
func (s *Statistics) pooled() [][]float64 {
	p := zeros(s.P)
	for a := 0; a < s.P; a++ {
		for b := 0; b < s.P; b++ {
			t := 0.0
			for _, sk := range s.Scatter {
				t += sk[a][b]
			}
			p[a][b] = t / float64(s.N-len(s.Counts))
		}
	}
	return p
}

type GaussianModel struct {
	Name                                           string
	Features                                       []int
	Stats                                          *Statistics
	Priors, LogPriors                              []float64
	Covariances, Factors                           [][][]float64
	LogDets                                        []float64
	Epsilon, Gamma, MaxVariance, Added, Normalizer float64
}

func trainModel(rows []Row, features []int, c int, name, prior string, epsilon, gamma float64) *GaussianModel {
	s := statistics(rows, features, c)
	m := &GaussianModel{Name: name, Features: append([]int{}, features...), Stats: s, Epsilon: epsilon,
		Gamma: gamma, Priors: make([]float64, c), LogPriors: make([]float64, c), Covariances: make([][][]float64,
			c), Factors: make([][][]float64, c), LogDets: make([]float64, c)}
	m.MaxVariance = s.Variances[0]
	for _, x := range s.Variances[1:] {
		if x > m.MaxVariance {
			m.MaxVariance = x
		}
	}
	m.Added = epsilon * m.MaxVariance
	m.Normalizer = float64(len(features)) * math.Log(2*math.Pi) / 2
	for k, count := range s.Counts {
		if prior == "empirical" {
			m.Priors[k] = float64(count) / float64(s.N)
		} else {
			m.Priors[k] = 1 / float64(c)
		}
		m.LogPriors[k] = math.Log(m.Priors[k])
	}
	if name == "LDA" {
		pooled := s.pooled()
		l := cholesky(pooled)
		ld := logDet(l)
		for k := 0; k < c; k++ {
			m.Covariances[k] = pooled
			m.Factors[k] = l
			m.LogDets[k] = ld
		}
	} else {
		for k, count := range s.Counts {
			cov := zeros(s.P)
			for a := 0; a < s.P; a++ {
				for b := 0; b < s.P; b++ {
					if name == "NB" {
						if a == b {
							cov[a][b] = s.Scatter[k][a][b]/float64(count) + m.Added
						}
					} else {
						value := s.Scatter[k][a][b] / float64(count-1)
						if a != b {
							value *= 1 - gamma
						}
						cov[a][b] = value
					}
				}
			}
			m.Covariances[k] = cov
			m.Factors[k] = cholesky(cov)
			m.LogDets[k] = logDet(m.Factors[k])
		}
	}
	return m
}
func argmax(v []float64) int {
	best := 0
	for i := 1; i < len(v); i++ {
		if v[i] > v[best] {
			best = i
		}
	}
	return best
}
func argmin(v []float64) int {
	best := 0
	for i := 1; i < len(v); i++ {
		if v[i] < v[best] {
			best = i
		}
	}
	return best
}
func (m *GaussianModel) vector(values []float64) []float64 {
	v := make([]float64, len(m.Features))
	for j, f := range m.Features {
		v[j] = values[f]
	}
	return v
}
func (m *GaussianModel) squaredDistances(v []float64) []float64 {
	q := make([]float64, len(m.Priors))
	for k, mean := range m.Stats.Means {
		delta := make([]float64, len(v))
		for j, x := range v {
			delta[j] = x - mean[j]
		}
		q[k] = quadratic(m.Factors[k], delta)
	}
	return q
}
func (m *GaussianModel) distances(values []float64) []float64 {
	return m.squaredDistances(m.vector(values))
}
func (m *GaussianModel) scores(v []float64) []float64 {
	q := m.squaredDistances(v)
	g := make([]float64, len(q))
	for k := range g {
		g[k] = m.LogPriors[k] - m.Normalizer - m.LogDets[k]/2 - q[k]/2
	}
	return g
}
func (m *GaussianModel) predict(values []float64) int { return argmax(m.scores(m.vector(values))) }

type Prediction struct {
	Predicted, Decision     int
	Posterior, LogPosterior []float64
	Confidence              float64
}

func (m *GaussianModel) inferVector(v []float64, costs [][]float64) Prediction {
	g := m.scores(v)
	pred := argmax(g)
	ex := make([]float64, len(g))
	total := 0.0
	for k, x := range g {
		ex[k] = math.Exp(x - g[pred])
		total += ex[k]
	}
	probs := make([]float64, len(g))
	logs := make([]float64, len(g))
	lt := math.Log(total)
	for k := range g {
		probs[k] = ex[k] / total
		logs[k] = (g[k] - g[pred]) - lt
	}
	decision := pred
	if costs != nil {
		risk := make([]float64, len(g))
		for b := range risk {
			for k, p := range probs {
				risk[b] += p * costs[k][b]
			}
		}
		decision = argmin(risk)
	}
	return Prediction{pred, decision, probs, logs, probs[argmax(probs)]}
}
func (m *GaussianModel) infer(values []float64, costs [][]float64) Prediction {
	return m.inferVector(m.vector(values), costs)
}
