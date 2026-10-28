package main

import "fmt"

type Point struct{ X, Y int64 }
type Center struct{ X, Y, D int64 }
type Edge [2]int
type Triangle [3]int

func orient(p, q, r Point) int64 { return (q.X-p.X)*(r.Y-p.Y) - (q.Y-p.Y)*(r.X-p.X) }
func d2(p, q Point) int64        { x, y := p.X-q.X, p.Y-q.Y; return x*x + y*y }
func dot(o, p, q Point) int64    { return (p.X-o.X)*(q.X-o.X) + (p.Y-o.Y)*(q.Y-o.Y) }
func incircle(a, b, c, d Point) int64 {
	ax, ay, bx, by, cx, cy := a.X-d.X, a.Y-d.Y, b.X-d.X, b.Y-d.Y, c.X-d.X, c.Y-d.Y
	aa, bb, cc := ax*ax+ay*ay, bx*bx+by*by, cx*cx+cy*cy
	return ax*(by*cc-bb*cy) - ay*(bx*cc-bb*cx) + aa*(bx*cy-by*cx)
}
func circumcenter(a, b, c Point) Center {
	bx, by, cx, cy := b.X-a.X, b.Y-a.Y, c.X-a.X, c.Y-a.Y
	bb, cc := bx*bx+by*by, cx*cx+cy*cy
	d := 2 * (bx*cy - by*cx)
	return Center{a.X*d + cy*bb - by*cc, a.Y*d + bx*cc - cx*bb, d}
}
func abs64(n int64) int64 {
	if n < 0 {
		return -n
	}
	return n
}
func gcd(a, b int64) int64 {
	a, b = abs64(a), abs64(b)
	for b != 0 {
		a, b = b, a%b
	}
	return a
}
func fraction(n, d int64) string {
	g := gcd(n, d)
	n, d = n/g, d/g
	if d == 1 {
		return fmt.Sprint(n)
	}
	return fmt.Sprintf("%d/%d", n, d)
}
func direction(dx, dy int64) Point { g := gcd(dx, dy); return Point{dx / g, dy / g} }
func orderedEdge(a, b int) Edge {
	if a > b {
		a, b = b, a
	}
	return Edge{a, b}
}
func edgeLess(a, b Edge) bool          { return a[0] < b[0] || a[0] == b[0] && a[1] < b[1] }
func triangleEdges(t Triangle) [3]Edge { return [3]Edge{{t[0], t[1]}, {t[1], t[2]}, {t[2], t[0]}} }
