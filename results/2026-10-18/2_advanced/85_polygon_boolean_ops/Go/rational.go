package main

import (
	"fmt"
	"math/big"
)

type Rational struct{ value *big.Rat }

func rational(n int64) Rational            { return Rational{big.NewRat(n, 1)} }
func ratio(n, d int64) Rational            { return Rational{big.NewRat(n, d)} }
func (a Rational) Add(b Rational) Rational { return Rational{new(big.Rat).Add(a.value, b.value)} }
func (a Rational) Sub(b Rational) Rational { return Rational{new(big.Rat).Sub(a.value, b.value)} }
func (a Rational) Mul(b Rational) Rational { return Rational{new(big.Rat).Mul(a.value, b.value)} }
func (a Rational) Div(b Rational) Rational { return Rational{new(big.Rat).Quo(a.value, b.value)} }
func (a Rational) Cmp(b Rational) int      { return a.value.Cmp(b.value) }
func (a Rational) Sign() int               { return a.value.Sign() }
func (a Rational) String() string          { return a.value.RatString() }
func (a Rational) Real() float64 {
	n, _ := new(big.Float).SetInt(a.value.Num()).Float64()
	d, _ := new(big.Float).SetInt(a.value.Denom()).Float64()
	return n / d
}
func (a Rational) Round() int64 {
	n := new(big.Int).Mul(a.value.Num(), big.NewInt(2))
	n.Add(n, a.value.Denom())
	d := new(big.Int).Mul(a.value.Denom(), big.NewInt(2))
	q, r := new(big.Int), new(big.Int)
	q.QuoRem(n, d, r)
	if n.Sign() < 0 && r.Sign() != 0 {
		q.Sub(q, big.NewInt(1))
	}
	return q.Int64()
}

type Point struct{ X, Y Rational }

func point(x, y int64) Point       { return Point{rational(x), rational(y)} }
func (p Point) Equal(q Point) bool { return p.X.Cmp(q.X) == 0 && p.Y.Cmp(q.Y) == 0 }
func (p Point) String() string     { return fmt.Sprintf("(%s,%s)", p.X, p.Y) }
func pointLess(p, q Point) bool {
	c := p.Y.Cmp(q.Y)
	if c != 0 {
		return c < 0
	}
	return p.X.Cmp(q.X) < 0
}
func cross(o, a, b Point) Rational {
	return a.X.Sub(o.X).Mul(b.Y.Sub(o.Y)).Sub(a.Y.Sub(o.Y).Mul(b.X.Sub(o.X)))
}
func along(a, b Point, t Rational) Point {
	return Point{a.X.Add(t.Mul(b.X.Sub(a.X))), a.Y.Add(t.Mul(b.Y.Sub(a.Y)))}
}
func segmentText(a, b Point) string { return a.String() + "-" + b.String() }
