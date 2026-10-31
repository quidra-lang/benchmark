package main

import "math"

type Optimizer struct {
	Config   RunConfig
	M, V     []float64
	Pi1, Pi2 float64
}

func newOptimizer(config RunConfig, n int) Optimizer {
	return Optimizer{config, make([]float64, n), make([]float64, n), 1, 1}
}
func (o *Optimizer) update(theta, g []float64, eta float64) {
	c := o.Config
	if c.Optimizer == "ADAM" {
		o.Pi1 *= c.Beta1
		o.Pi2 *= c.Beta2
	}
	for p, v := range g {
		switch c.Optimizer {
		case "SGD":
			theta[p] = theta[p] - eta*v
		case "MOMENTUM":
			o.V[p] = c.Mu*o.V[p] + v
			theta[p] = theta[p] - eta*o.V[p]
		case "ADAM":
			o.M[p] = c.Beta1*o.M[p] + (1-c.Beta1)*v
			o.V[p] = c.Beta2*o.V[p] + (1-c.Beta2)*v*v
			mh, vh := o.M[p]/(1-o.Pi1), o.V[p]/(1-o.Pi2)
			theta[p] = theta[p] - eta*mh/(math.Sqrt(vh)+c.Epsilon)
		}
	}
}
func learningRate(config RunConfig, params Params, epoch int) float64 {
	eta := config.Eta
	for i := 0; i < (epoch-1)/params.Step; i++ {
		eta *= params.Gamma
	}
	return eta
}
