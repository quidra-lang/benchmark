package main

import "math"

type RandomGenerator struct{ State int64 }

func (r *RandomGenerator) draw() int64     { r.State = 48271 * r.State % 2147483647; return r.State }
func (r *RandomGenerator) factor() float64 { return float64(r.draw()%2001-1000) / 10000 }
func dot(a, b []float64) float64 {
	sum := 0.0
	for f, x := range a {
		sum += x * b[f]
	}
	return sum
}
func zeros(rows, cols int) [][]float64 {
	a := make([][]float64, rows)
	for i := range a {
		a[i] = make([]float64, cols)
	}
	return a
}

type FactorModel struct {
	Mean               float64
	Users, Items       [][]float64
	UserBias, ItemBias []float64
}

func (m FactorModel) predict(u, i int) float64 {
	return ((m.Mean + m.UserBias[u]) + m.ItemBias[i]) + dot(m.Users[u], m.Items[i])
}

type TrainingRecord struct {
	Method string
	Epoch  int
	RMSE   float64
}

func trainSVD(d *Ratings) (FactorModel, []TrainingRecord) {
	p := d.Params
	rng := RandomGenerator{p.Seed}
	users, items := zeros(len(d.Users), p.Factors), zeros(len(d.Items), p.Factors)
	for u := range users {
		for f := range users[u] {
			users[u][f] = rng.factor()
		}
	}
	for i := range items {
		for f := range items[i] {
			items[i][f] = rng.factor()
		}
	}
	m := FactorModel{d.Mean, users, items, make([]float64, len(users)), make([]float64, len(items))}
	order := make([]int, len(d.Training))
	for j := range order {
		order[j] = j
	}
	log := []TrainingRecord{}
	for epoch := 1; epoch <= p.Epochs; epoch++ {
		for t := len(order) - 1; t >= 1; t-- {
			y := int(rng.draw() % int64(t+1))
			order[t], order[y] = order[y], order[t]
		}
		for _, j := range order {
			r := d.Training[j]
			u, i := r.User, r.Item
			e := float64(r.Value) - m.predict(u, i)
			m.UserBias[u] += p.Rate * (e - p.Regularization*m.UserBias[u])
			m.ItemBias[i] += p.Rate * (e - p.Regularization*m.ItemBias[i])
			for f := 0; f < p.Factors; f++ {
				a, b := users[u][f], items[i][f]
				users[u][f] = a + p.Rate*(e*b-p.Regularization*a)
				items[i][f] = b + p.Rate*(e*a-p.Regularization*b)
			}
		}
		log = append(log, TrainingRecord{"SVD", epoch, trainingRMSE(d.Training, m.predict)})
	}
	return m, log
}
func choleskySolve(a [][]float64, w []float64) []float64 {
	n := len(w)
	l := zeros(n, n)
	for i := 0; i < n; i++ {
		for j := 0; j <= i; j++ {
			sum := 0.0
			for k := 0; k < j; k++ {
				sum += l[i][k] * l[j][k]
			}
			s := a[i][j] - sum
			if i == j {
				l[i][j] = math.Sqrt(s)
			} else {
				l[i][j] = s / l[j][j]
			}
		}
	}
	z := make([]float64, n)
	for i := 0; i < n; i++ {
		sum := 0.0
		for k := 0; k < i; k++ {
			sum += l[i][k] * z[k]
		}
		z[i] = (w[i] - sum) / l[i][i]
	}
	x := make([]float64, n)
	for i := n - 1; i >= 0; i-- {
		sum := 0.0
		for k := i + 1; k < n; k++ {
			sum += l[k][i] * x[k]
		}
		x[i] = (z[i] - sum) / l[i][i]
	}
	return x
}
func fitVector(vectors [][]float64, residuals []float64, factors int, regularization float64) []float64 {
	a := zeros(factors, factors)
	w := make([]float64, factors)
	for i, v := range vectors {
		for row := 0; row < factors; row++ {
			w[row] += residuals[i] * v[row]
			for col := 0; col < factors; col++ {
				a[row][col] += v[row] * v[col]
			}
		}
	}
	for row := 0; row < factors; row++ {
		a[row][row] += regularization * float64(len(vectors))
	}
	return choleskySolve(a, w)
}
func trainALS(d *Ratings, userBias, itemBias []float64) (FactorModel, []TrainingRecord) {
	p := d.Params
	rng := RandomGenerator{p.Seed}
	users, items := zeros(len(d.Users), p.Factors), zeros(len(d.Items), p.Factors)
	for i := range items {
		for f := range items[i] {
			items[i][f] = rng.factor()
		}
	}
	m := FactorModel{d.Mean, users, items, userBias, itemBias}
	residual := zeros(len(d.Users), len(d.Items))
	for _, r := range d.Training {
		residual[r.User][r.Item] = float64(r.Value) - ((d.Mean + userBias[r.User]) + itemBias[r.Item])
	}
	log := []TrainingRecord{}
	for iteration := 1; iteration <= p.ALSIterations; iteration++ {
		for u, ratings := range d.ByUser {
			vectors := [][]float64{}
			targets := []float64{}
			for _, r := range ratings {
				vectors = append(vectors, items[r.Other])
				targets = append(targets, residual[u][r.Other])
			}
			users[u] = fitVector(vectors, targets, p.Factors, p.ALSReg)
		}
		for i, ratings := range d.ByItem {
			vectors := [][]float64{}
			targets := []float64{}
			for _, r := range ratings {
				vectors = append(vectors, users[r.Other])
				targets = append(targets, residual[r.Other][i])
			}
			items[i] = fitVector(vectors, targets, p.Factors, p.ALSReg)
		}
		log = append(log, TrainingRecord{"ALS", iteration, trainingRMSE(d.Training, m.predict)})
	}
	return m, log
}
