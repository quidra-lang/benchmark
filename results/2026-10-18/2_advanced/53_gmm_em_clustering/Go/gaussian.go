package main

import "math"

func determinant(s Covariance) float64 { return s.A*s.C - s.B*s.B }
func mahalanobis(point, mean Point, s Covariance) float64 {
	dx, dy := point.X-mean.X, point.Y-mean.Y
	return (s.C*dx*dx - 2*s.B*dx*dy + s.A*dy*dy) / determinant(s)
}
func weightedLogDensity(point Point, c Component) float64 {
	return math.Log(c.Weight) - math.Log(2*math.Pi) - math.Log(determinant(c.Cov))/2 - mahalanobis(point, c.Mean, c.Cov)/2
}

type EigenData struct {
	Leading, Trailing                      float64
	Direction                              Point
	Angle, Major, Minor, Area, Correlation float64
}

func eigenData(s Covariance) EigenData {
	h := (s.A + s.C) / 2
	d := (s.A - s.C) / 2
	g := math.Sqrt(d*d + s.B*s.B)
	leading, trailing := h+g, h-g
	direction := Point{1, 0}
	if s.B == 0 {
		if s.A < s.C {
			direction = Point{0, 1}
		}
	} else {
		vx, vy := leading-s.C, s.B
		if s.A < s.C {
			vx, vy = s.B, leading-s.A
		}
		length := math.Sqrt(vx*vx + vy*vy)
		if vx < 0 {
			vx, vy = -vx, -vy
		}
		direction = Point{vx / length, vy / length}
	}
	return EigenData{leading, trailing, direction, math.Atan2(direction.Y, direction.X) * 180 / math.Pi,
		math.Sqrt(leading), math.Sqrt(trailing), math.Pi * math.Sqrt(leading*trailing), s.B / math.Sqrt(s.A*s.C)}
}
func bhattacharyya(a, b Component) (float64, float64) {
	mean := Covariance{(a.Cov.A + b.Cov.A) / 2, (a.Cov.B + b.Cov.B) / 2, (a.Cov.C + b.Cov.C) / 2}
	d := mahalanobis(b.Mean, a.Mean, mean)/8 + math.Log(determinant(mean)/math.Sqrt(determinant(a.Cov)*determinant(b.Cov)))/2
	return d, math.Exp(-d)
}
