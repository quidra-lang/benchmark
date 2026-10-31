package main

import (
	"os"
	"strconv"
	"strings"
)

type Image struct {
	ID     string
	Label  int
	Pixels string
	Input  []float64
}
type RunConfig struct {
	Name, Network, Optimizer               string
	Eta, Lambda, Mu, Beta1, Beta2, Epsilon float64
}
type Params struct {
	Seed, Batch, Epochs, Patience, Step, Stride, Bins int
	Gamma                                             float64
	Prune, Noise                                      []int
	Runs                                              []RunConfig
}

func lines(path string) []string {
	b, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	return strings.Split(strings.TrimSuffix(string(b), "\n"), "\n")
}
func integer(s string) int {
	v, e := strconv.Atoi(s)
	if e != nil {
		panic(e)
	}
	return v
}
func number(s string) float64 {
	v, e := strconv.ParseFloat(s, 64)
	if e != nil {
		panic(e)
	}
	return v
}
func readImages(path string) []Image {
	out := []Image{}
	for _, line := range lines(path)[1:] {
		a := strings.Split(line, ",")
		image := Image{ID: a[0], Label: integer(a[1]), Pixels: a[2], Input: make([]float64, len(a[2]))}
		for i, c := range a[2] {
			if c == '1' {
				image.Input[i] = 1
			}
		}
		out = append(out, image)
	}
	return out
}
func readNetworks() ([]Network, int, int) {
	a := lines("input/network.txt")
	header := strings.Fields(a[0])
	w, h := integer(header[1]), integer(header[2])
	out := []Network{}
	current := -1
	for _, line := range a[1:] {
		if line == "" {
			continue
		}
		f := strings.Fields(line)
		if f[0] == "NETWORK" {
			out = append(out, Network{Name: f[1]})
			current++
		} else {
			n := &out[current]
			inputs := w * h
			if len(n.Layers) > 0 {
				inputs = n.Layers[len(n.Layers)-1].Units
			}
			n.Layers = append(n.Layers, Layer{Inputs: inputs, Units: integer(f[1]), Activation: f[2], Weights: len(n.Initial),
				Biases: len(n.Initial) + integer(f[1])*inputs})
			n.Initial = append(n.Initial, make([]float64, integer(f[1])*(inputs+1))...)
		}
	}
	index := map[string]int{}
	for i := range out {
		index[out[i].Name] = i
		for _, layer := range out[i].Layers {
			for p := layer.Weights; p < layer.Biases; p++ {
				out[i].WeightIndices = append(out[i].WeightIndices, p)
			}
		}
	}
	current = -1
	offset := 0
	for _, line := range lines("input/weights.txt") {
		if line == "" {
			continue
		}
		f := strings.Fields(line)
		if f[0] == "NETWORK" {
			current = index[f[1]]
			offset = 0
		} else if f[0] == "W" || f[0] == "B" {
			for _, s := range f[1:] {
				out[current].Initial[offset] = number(s)
				offset++
			}
		}
	}
	return out, w, h
}
func readParams() Params {
	p := Params{}
	for _, line := range lines("input/params.txt") {
		a := strings.Fields(line)
		switch a[0] {
		case "SEED":
			p.Seed = integer(a[1])
		case "BATCH_SIZE":
			p.Batch = integer(a[1])
		case "MAX_EPOCHS":
			p.Epochs = integer(a[1])
		case "PATIENCE":
			p.Patience = integer(a[1])
		case "LR_STEP":
			p.Step, p.Gamma = integer(a[1]), number(a[2])
		case "GRADIENT_CHECK_STRIDE":
			p.Stride = integer(a[1])
		case "CALIBRATION_BINS":
			p.Bins = integer(a[1])
		case "PRUNE":
			for _, s := range a[1:] {
				p.Prune = append(p.Prune, integer(s))
			}
		case "NOISE":
			for _, s := range a[1:] {
				p.Noise = append(p.Noise, integer(s))
			}
		case "RUN":
			r := RunConfig{Name: a[1], Network: a[2], Optimizer: a[3], Eta: number(a[4]), Lambda: number(a[5])}
			if r.Optimizer == "MOMENTUM" {
				r.Mu = number(a[6])
			} else if r.Optimizer == "ADAM" {
				r.Beta1, r.Beta2, r.Epsilon = number(a[6]), number(a[7]), number(a[8])
			}
			p.Runs = append(p.Runs, r)
		}
	}
	return p
}

type RNG struct{ State int64 }

func (r *RNG) next() int { r.State = 48271 * r.State % 2147483647; return int(r.State) }
func (r *RNG) shuffle(a []int) {
	for i := len(a) - 1; i >= 1; i-- {
		j := r.next() % (i + 1)
		a[i], a[j] = a[j], a[i]
	}
}
