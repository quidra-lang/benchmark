package main

type Face struct {
	Neighbor int
	G, Theta float64
	Boundary bool
}
type Plate struct {
	Mesh             Mesh
	Faces            [][4]Face
	C, A, Beta, Sall []float64
	Materials        []Material
	MaterialIndex    []int
}

func flows(plate *Plate, x []float64, p, first, last int) float64 {
	s := 0.0
	for face := first; face <= last; face++ {
		f := plate.Faces[p][face]
		if f.Neighbor >= 0 {
			s += f.G * (x[f.Neighbor] - x[p])
		} else if f.Boundary {
			s += f.G * (f.Theta - x[p])
		}
	}
	return s
}
func thomas(lower, diagonal, upper, rhs []float64) []float64 {
	n := len(rhs)
	nu, phi, y := make([]float64, n), make([]float64, n), make([]float64, n)
	nu[0], phi[0] = upper[0]/diagonal[0], rhs[0]/diagonal[0]
	for i := 1; i < n; i++ {
		kappa := diagonal[i] - lower[i]*nu[i-1]
		nu[i] = upper[i] / kappa
		phi[i] = (rhs[i] - lower[i]*phi[i-1]) / kappa
	}
	y[n-1] = phi[n-1]
	for i := n - 2; i >= 0; i-- {
		y[i] = phi[i] - nu[i]*y[i+1]
	}
	return y
}
func sweep(plate *Plate, tau float64, rhs []float64, horizontal bool) []float64 {
	mesh := plate.Mesh
	groups, size, first := mesh.W, mesh.H, 2
	if horizontal {
		groups, size, first = mesh.H, mesh.W, 0
	}
	out := make([]float64, len(rhs))
	for group := 0; group < groups; group++ {
		cells := make([]int, size)
		lower, diagonal, upper, phi := make([]float64, size), make([]float64, size), make([]float64, size), make([]float64, size)
		for i := 0; i < size; i++ {
			p := i*mesh.W + group
			if horizontal {
				p = group*mesh.W + i
			}
			cells[i] = p
			l, r := plate.Faces[p][first], plate.Faces[p][first+1]
			if l.Neighbor >= 0 {
				lower[i] = -l.G
			}
			if r.Neighbor >= 0 {
				upper[i] = -r.G
			}
			diagonal[i] = plate.C[p]/tau + l.G + r.G
			phi[i] = rhs[p]
			if l.Boundary {
				phi[i] += l.G * l.Theta
			}
			if r.Boundary {
				phi[i] += r.G * r.Theta
			}
		}
		y := thomas(lower, diagonal, upper, phi)
		for i, p := range cells {
			out[p] = y[i]
		}
	}
	return out
}
func step(plate *Plate, old, source []float64, dt float64, method string) ([]float64, []float64) {
	n := len(old)
	rhs := make([]float64, n)
	if method == "ftcs" {
		for p := range old {
			rhs[p] = old[p] + dt*(flows(plate, old, p, 0, 3)+source[p])/plate.C[p]
		}
		return rhs, nil
	}
	tau := dt
	if method == "crank_nicolson" {
		tau = dt / 2
	}
	for p := range old {
		rhs[p] = plate.C[p]/tau*old[p] + flows(plate, old, p, 2, 3) + source[p]
	}
	y := sweep(plate, tau, rhs, true)
	for p := range old {
		if method == "backward_euler" {
			rhs[p] = plate.C[p]/dt*y[p] - flows(plate, old, p, 2, 3)
		} else {
			rhs[p] = plate.C[p]/tau*y[p] + flows(plate, y, p, 0, 1) + source[p]
		}
	}
	return sweep(plate, tau, rhs, false), y
}
