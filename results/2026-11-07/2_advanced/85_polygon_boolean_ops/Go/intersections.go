package main

func between(value, a, b Rational) bool {
	if a.Cmp(b) > 0 {
		a, b = b, a
	}
	return a.Cmp(value) <= 0 && value.Cmp(b) <= 0
}
func onSegment(p, a, b Point) bool {
	return cross(a, b, p).Sign() == 0 && between(p.X, a.X, b.X) && between(p.Y, a.Y, b.Y)
}
func touching(a, b, c, d Point) bool {
	abC, abD, cdA, cdB := cross(a, b, c).Sign(), cross(a, b, d).Sign(), cross(c, d, a).Sign(), cross(c, d, b).Sign()
	return abC*abD < 0 && cdA*cdB < 0 || onSegment(c, a, b) || onSegment(d, a, b) || onSegment(a, c, d) || onSegment(b, c, d)
}
func overlapping(a, b, c, d Point) bool {
	if cross(a, b, c).Sign() != 0 || cross(a, b, d).Sign() != 0 {
		return false
	}
	aa, bb, cc, dd := a.X, b.X, c.X, d.X
	if a.X.Cmp(b.X) == 0 {
		aa, bb, cc, dd = a.Y, b.Y, c.Y, d.Y
	}
	if aa.Cmp(bb) > 0 {
		aa, bb = bb, aa
	}
	if cc.Cmp(dd) > 0 {
		cc, dd = dd, cc
	}
	if cc.Cmp(aa) > 0 {
		aa = cc
	}
	if dd.Cmp(bb) < 0 {
		bb = dd
	}
	return aa.Cmp(bb) < 0
}
func crossing(a, b, c, d Point) (Rational, Rational, Point, bool) {
	rx, ry, sx, sy := b.X.Sub(a.X), b.Y.Sub(a.Y), d.X.Sub(c.X), d.Y.Sub(c.Y)
	den := rx.Mul(sy).Sub(ry.Mul(sx))
	if den.Sign() == 0 {
		return Rational{}, Rational{}, Point{}, false
	}
	gx, gy := c.X.Sub(a.X), c.Y.Sub(a.Y)
	t := gx.Mul(sy).Sub(gy.Mul(sx)).Div(den)
	u := gx.Mul(ry).Sub(gy.Mul(rx)).Div(den)
	if t.Sign() <= 0 || t.Cmp(rational(1)) >= 0 || u.Sign() <= 0 || u.Cmp(rational(1)) >= 0 {
		return Rational{}, Rational{}, Point{}, false
	}
	return t, u, along(a, b, t), true
}
func lineIntersection(a, b, c, d Point) Point {
	first, second := cross(c, d, a), cross(c, d, b)
	return along(a, b, first.Div(first.Sub(second)))
}
