package main

type Layer struct {
	Inputs, Units   int
	Activation      string
	Weights, Biases int
}
type Network struct {
	Name          string
	Layers        []Layer
	Initial       []float64
	WeightIndices []int
}
type Forward struct {
	Activations, Z      [][]float64
	Scores, OutputDelta []float64
	Loss                float64
	Prediction          int
	Confidence          float64
}

func (n Network) forward(theta []float64, image Image) Forward {
	out := Forward{Activations: [][]float64{image.Input}, Z: make([][]float64, len(n.Layers))}
	for l, layer := range n.Layers {
		z := preactivations(layer, theta, out.Activations[l])
		out.Z[l] = z
		if l+1 == len(n.Layers) {
			out.Scores, out.Loss, out.OutputDelta = output(layer.Activation, z, image.Label)
			out.Activations = append(out.Activations, out.Scores)
		} else {
			a := make([]float64, len(z))
			for j, v := range z {
				a[j] = activation(layer.Activation, v)
			}
			out.Activations = append(out.Activations, a)
		}
	}
	out.Prediction = prediction(out.Scores)
	out.Confidence = out.Scores[out.Prediction]
	return out
}
func (n Network) gradient(theta []float64, image Image) ([]float64, []float64, float64) {
	f := n.forward(theta, image)
	deltas := make([][]float64, len(n.Layers))
	last := len(n.Layers) - 1
	deltas[last] = f.OutputDelta
	for l := last - 1; l >= 0; l-- {
		layer := n.Layers[l]
		delta := make([]float64, layer.Units)
		for j := range delta {
			delta[j] = propagate(n.Layers[l+1], theta, deltas[l+1], j) * derivative(layer.Activation, f.Z[l][j], f.Activations[l+1][j])
		}
		deltas[l] = delta
	}
	gradient := make([]float64, len(theta))
	for l, layer := range n.Layers {
		for j, d := range deltas[l] {
			for i, a := range f.Activations[l] {
				gradient[layer.Weights+j*layer.Inputs+i] = d * a
			}
			gradient[layer.Biases+j] = d
		}
	}
	input := make([]float64, n.Layers[0].Inputs)
	for i := range input {
		input[i] = propagate(n.Layers[0], theta, deltas[0], i)
	}
	return gradient, input, f.Loss
}
func (n Network) meanGradient(theta []float64, data []Image, indices []int) ([]float64, float64) {
	out := make([]float64, len(theta))
	loss := 0.0
	for _, index := range indices {
		g, _, v := n.gradient(theta, data[index])
		loss += v
		for p, x := range g {
			out[p] += x
		}
	}
	for p := range out {
		out[p] /= float64(len(indices))
	}
	return out, loss / float64(len(indices))
}
