package main

func squaredRadius(a, b, c Point) float64 {
	l1, l2, l3, area := float64(d2(a, b)), float64(d2(b, c)), float64(d2(c, a)), float64(orient(a, b, c))
	return ((l1 * l2) * l3) / ((4 * area) * area)
}
func position(center Center, points []Point, hull []int) string {
	on := false
	for i, u := range hull {
		v := hull[(i+1)%len(hull)]
		a, b := points[u], points[v]
		sigma := (b.X-a.X)*(center.Y-a.Y*center.D) - (b.Y-a.Y)*(center.X-a.X*center.D)
		if sigma < 0 {
			return "outside"
		}
		if sigma == 0 {
			on = true
		}
	}
	if on {
		return "on"
	}
	return "inside"
}
func neighborOrder(s int, neighbors []int, directed map[Edge]int, hullNext map[int]int) []int {
	first := hullNext[s]
	if first == 0 {
		first = neighbors[0]
		for _, v := range neighbors[1:] {
			first = min(first, v)
		}
	}
	out := []int{first}
	for len(out) < len(neighbors) {
		out = append(out, directed[Edge{s, out[len(out)-1]}])
	}
	return out
}
func outward(points []Point, u, v int) Point {
	return direction(points[v].Y-points[u].Y, points[u].X-points[v].X)
}

type RealPoint struct{ X, Y float64 }

func boundedArea(site Point, centers []Center) float64 {
	relative := make([]RealPoint, len(centers))
	for i, c := range centers {
		relative[i] = RealPoint{float64(c.X)/float64(c.D) - float64(site.X), float64(c.Y)/float64(c.D) - float64(site.Y)}
	}
	total := 0.0
	for i, p := range relative {
		q := relative[(i+1)%len(relative)]
		total += p.X*q.Y - q.X*p.Y
	}
	return total / 2
}
func clippedArea(points []Point, s int, neighbors []int) float64 {
	polygon := []RealPoint{{0, 0}, {1000, 0}, {1000, 1000}, {0, 1000}}
	site := points[s]
	for _, t := range neighbors {
		other := points[t]
		c1, c2, c3 := float64(2*(other.X-site.X)), float64(2*(other.Y-site.Y)), float64(other.X*other.X+other.Y*other.Y-site.X*site.X-site.Y*site.Y)
		clipped := []RealPoint{}
		for i, p := range polygon {
			q := polygon[(i+1)%len(polygon)]
			fp, fq := c1*p.X+c2*p.Y-c3, c1*q.X+c2*q.Y-c3
			if fp <= 0 {
				clipped = append(clipped, p)
			}
			if fp < 0 && fq > 0 || fq < 0 && fp > 0 {
				lambda := fp / (fp - fq)
				clipped = append(clipped, RealPoint{p.X + (q.X-p.X)*lambda, p.Y + (q.Y-p.Y)*lambda})
			}
		}
		polygon = clipped
	}
	total := 0.0
	for i, p := range polygon {
		q := polygon[(i+1)%len(polygon)]
		total += p.X*q.Y - q.X*p.Y
	}
	return total / 2
}
