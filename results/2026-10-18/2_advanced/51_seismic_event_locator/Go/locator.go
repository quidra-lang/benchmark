package main

import "math"

const pi = 3.141592653589793

type Solution [4]float64
type Observation struct {
	Station *Station
	Time    float64
}
type GridResult struct {
	Solution Solution
	RMS      float64
	Profile  []float64
}
type Iteration struct {
	Number   int
	Solution Solution
	RMS      float64
}
type LocationRun struct {
	Solution  Solution
	RMS       float64
	Trace     []Iteration
	Residuals []float64
	Grid      *GridResult
}
type Ellipse struct{ SMaj, SMin, Az, Erz, Ert float64 }

func distance(solution Solution, s *Station) float64 {
	dx, dy, dz := solution[0]-float64(s.X), solution[1]-float64(s.Y), solution[2]+float64(s.Elevation)
	return math.Sqrt(dx*dx + dy*dy + dz*dz)
}
func residuals(solution Solution, observations []Observation, velocity float64) []float64 {
	values := make([]float64, len(observations))
	for i, o := range observations {
		values[i] = o.Time - solution[3] - distance(solution, o.Station)/velocity
	}
	return values
}
func rms(solution Solution, observations []Observation, velocity float64) float64 {
	values := residuals(solution, observations, velocity)
	total := 0.0
	for _, v := range values {
		total += v * v
	}
	return math.Sqrt(total / float64(len(values)))
}
func gridSearch(observations []Observation, p Params) GridResult {
	velocity := p.real("velocity", 0)
	out := GridResult{}
	best := math.Inf(1)
	zmin, zmax, zstep := p.integer("grid_z", 0), p.integer("grid_z", 1), p.integer("grid_z", 2)
	profile := make([]float64, (zmax-zmin)/zstep+1)
	for i := range profile {
		profile[i] = math.Inf(1)
	}
	for x := p.integer("grid_x", 0); x <= p.integer("grid_x", 1); x += p.integer("grid_x", 2) {
		for y := p.integer("grid_y", 0); y <= p.integer("grid_y", 1); y += p.integer("grid_y", 2) {
			for z := zmin; z <= zmax; z += zstep {
				solution := Solution{float64(x), float64(y), float64(z), 0}
				deltas := make([]float64, len(observations))
				for i, o := range observations {
					deltas[i] = o.Time - distance(solution, o.Station)/velocity
				}
				origin := sum(deltas) / float64(len(deltas))
				error := 0.0
				for _, v := range deltas {
					d := v - origin
					error += d * d
				}
				if error < best {
					best = error
					solution[3] = origin
					out.Solution = solution
				}
				index := (z - zmin) / zstep
				if error < profile[index] {
					profile[index] = error
				}
			}
		}
	}
	out.RMS = math.Sqrt(best / float64(len(observations)))
	for _, v := range profile {
		out.Profile = append(out.Profile, math.Sqrt(v/float64(len(observations))))
	}
	return out
}
func cholesky(a [4][4]float64) [4][4]float64 {
	l := [4][4]float64{}
	for row := 0; row < 4; row++ {
		for col := 0; col <= row; col++ {
			total := 0.0
			for j := 0; j < col; j++ {
				total += l[row][j] * l[col][j]
			}
			value := a[row][col] - total
			if row == col {
				l[row][col] = math.Sqrt(value)
			} else {
				l[row][col] = value / l[col][col]
			}
		}
	}
	return l
}
func choleskySolve(l [4][4]float64, b [4]float64) [4]float64 {
	u, x := [4]float64{}, [4]float64{}
	for row := 0; row < 4; row++ {
		total := 0.0
		for col := 0; col < row; col++ {
			total += l[row][col] * u[col]
		}
		u[row] = (b[row] - total) / l[row][row]
	}
	for row := 3; row >= 0; row-- {
		total := 0.0
		for col := row + 1; col < 4; col++ {
			total += l[col][row] * x[col]
		}
		x[row] = (u[row] - total) / l[row][row]
	}
	return x
}
func normals(solution Solution, observations []Observation, velocity float64) ([4][4]float64, [4]float64) {
	a, b := [4][4]float64{}, [4]float64{}
	values := residuals(solution, observations, velocity)
	for i, o := range observations {
		d := distance(solution, o.Station)
		g := [4]float64{(solution[0] - float64(o.Station.X)) / (velocity * d), (solution[1] - float64(o.Station.Y)) / (velocity * d),
			(solution[2] + float64(o.Station.Elevation)) / (velocity * d), 1}
		for row := 0; row < 4; row++ {
			b[row] += g[row] * values[i]
			for col := 0; col < 4; col++ {
				a[row][col] += g[row] * g[col]
			}
		}
	}
	return a, b
}
func geiger(initial Solution, observations []Observation, velocity float64) LocationRun {
	solution := initial
	out := LocationRun{}
	for i := 1; i <= 8; i++ {
		a, b := normals(solution, observations, velocity)
		delta := choleskySolve(cholesky(a), b)
		for axis := 0; axis < 4; axis++ {
			solution[axis] += delta[axis]
		}
		if solution[2] < 0 {
			solution[2] = 0
		}
		out.Trace = append(out.Trace, Iteration{i, solution, rms(solution, observations, velocity)})
	}
	out.Solution = solution
	out.Residuals = residuals(solution, observations, velocity)
	out.RMS = rms(solution, observations, velocity)
	return out
}
func runLocation(observations []Observation, p Params) LocationRun {
	grid := gridSearch(observations, p)
	out := geiger(grid.Solution, observations, p.real("velocity", 0))
	out.Grid = &grid
	return out
}
func errorEllipse(solution Solution, observations []Observation, velocity float64) Ellipse {
	a, _ := normals(solution, observations, velocity)
	lower := cholesky(a)
	inverse := [4][4]float64{}
	for col := 0; col < 4; col++ {
		unit := [4]float64{}
		unit[col] = 1
		values := choleskySolve(lower, unit)
		for row := 0; row < 4; row++ {
			inverse[row][col] = values[row]
		}
	}
	total := 0.0
	for _, v := range residuals(solution, observations, velocity) {
		total += v * v
	}
	variance := total / float64(len(observations)-4)
	xx, yy, xy := variance*inverse[0][0], variance*inverse[1][1], variance*inverse[0][1]
	mu := (xx + yy) / 2
	d := (xx - yy) / 2
	rho := math.Sqrt(d*d + xy*xy)
	theta := math.Atan2(2*xy, xx-yy) / 2 * 180 / pi
	return Ellipse{math.Sqrt(mu + rho), math.Sqrt(mu - rho), 90 - theta, math.Sqrt(variance * inverse[2][2]), math.Sqrt(variance * inverse[3][3])}
}
