package main

import (
	"os"
	"strconv"
	"strings"
)

type Material struct {
	Name        string
	Color       Vec
	KD, KS      int64
	Exponent    int
	KR, KT, IOR int64
	Checker     bool
	Second      Vec
	Size        int64
}
type Object struct {
	ID                         int
	Label, Kind                string
	Material                   *Material
	P, N, Lo, Hi               Vec
	Radius                     int64
	Bound                      Bounds
	LeafDepth                  int
	Primary, Secondary, Shadow int64
}
type Light struct {
	Kind                                             string
	P, Direction, U, V                               Vec
	Outer, Inner, Intensity                          int64
	K                                                int
	Shadow, Blocked, Attenuated, Backfacing, Outside int64
}
type Fog struct {
	Color      Vec
	Start, End int64
}
type Scene struct {
	Eye, Forward, Right, Up Vec
	HW, HH, Ambient         int64
	Background              Vec
	Fog                     *Fog
	Objects                 []*Object
	Lights                  []*Light
}

func readText(path string) string {
	b, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	return string(b)
}
func parseInt(s string) int64 {
	v, e := strconv.ParseInt(s, 10, 64)
	if e != nil {
		panic(e)
	}
	return v
}
func ints(a []string) []int64 {
	v := make([]int64, len(a))
	for i, s := range a {
		v[i] = parseInt(s)
	}
	return v
}
func vector(a []int64) Vec { return Vec{a[0], a[1], a[2]} }
func readScene() Scene {
	s := Scene{}
	materials := map[string]*Material{}
	for _, line := range strings.Split(readText("input/scene.txt"), "\n") {
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		a := strings.Fields(line)
		switch a[0] {
		case "material":
			v := ints(a[2:])
			m := &Material{Name: a[1], Color: vector(v), KD: v[3], KS: v[4], Exponent: int(v[5]), KR: v[6], KT: v[7], IOR: v[8]}
			materials[a[1]] = m
		case "checker":
			v := ints(a[2:])
			m := materials[a[1]]
			m.Checker, m.Second, m.Size = true, vector(v), v[3]
		case "sphere", "plane", "box":
			v := ints(a[3:])
			o := &Object{ID: len(s.Objects), Label: a[1], Kind: a[0], Material: materials[a[2]]}
			if a[0] == "sphere" {
				o.P, o.Radius = vector(v), v[3]
			} else if a[0] == "plane" {
				o.P, o.N = vector(v), norm(vector(v[3:]))
			} else {
				o.Lo, o.Hi = vector(v), vector(v[3:])
			}
			s.Objects = append(s.Objects, o)
		case "point", "spot", "sun", "area":
			v := ints(a[1:])
			l := &Light{Kind: a[0], K: 1}
			switch a[0] {
			case "point":
				l.P, l.Intensity = vector(v), v[3]
			case "spot":
				l.P, l.Direction, l.Outer, l.Inner, l.Intensity = vector(v), norm(vector(v[3:])), v[6], v[7], v[8]
			case "sun":
				l.Direction, l.Intensity = norm(neg(vector(v))), v[3]
			case "area":
				l.P, l.U, l.V, l.K, l.Intensity = vector(v), vector(v[3:]), vector(v[6:]), int(v[9]), v[10]
			}
			s.Lights = append(s.Lights, l)
		default:
			v := ints(a[1:])
			switch a[0] {
			case "eye":
				s.Eye = vector(v)
			case "forward":
				s.Forward = vector(v)
			case "right":
				s.Right = vector(v)
			case "up":
				s.Up = vector(v)
			case "view":
				s.HW, s.HH = v[0], v[1]
			case "background":
				s.Background = vector(v)
			case "ambient":
				s.Ambient = v[0]
			case "fog":
				s.Fog = &Fog{vector(v), v[3], v[4]}
			}
		}
	}
	return s
}
