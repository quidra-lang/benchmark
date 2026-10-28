package main

import (
	"fmt"
	"os"
	"sort"
	"strings"
)

var rayKinds = []string{"primary", "reflection", "refraction", "shadow"}

type Settings struct {
	W, H, Contrast, Depth int
	Far, Epsilon, Pad     int64
}
type Node struct {
	Box         Bounds
	Depth       int
	Objects     []*Object
	Left, Right *Node
	Visits      int64
}
type Sample struct {
	Direction           Vec
	Distance, Intensity int64
}
type TraceContext struct {
	Rays  int64
	Depth int
}
type Result struct {
	Color               Vec
	Hit                 *Hit
	Point, Normal, Base Vec
	Illumination        int
	Lit                 []int
}
type Pixel struct {
	Center  Result
	Color   Vec
	Samples int
	Rays    int64
	Depth   int
}
type Renderer struct {
	Scene                                Scene
	Settings                             Settings
	Root                                 *Node
	Active                               bool
	Rays, Misses, NodeTests, ObjectTests [4]int64
	Depths                               []int64
	TIR, Clamped                         int64
	Pixels                               []Pixel
	Supersampled                         int
}

func readSettings() Settings {
	lines := strings.Split(strings.TrimSuffix(readText("input/render.txt"), "\n"), "\n")
	v := [][]int64{}
	for _, line := range lines {
		v = append(v, ints(strings.Fields(line)[1:]))
	}
	return Settings{int(v[0][0]), int(v[0][1]), int(v[1][0]), int(v[2][0]), v[3][0], v[4][0], v[5][0]}
}
func union(objects []*Object) Bounds {
	b := objects[0].Bound
	for _, o := range objects[1:] {
		for a := 0; a < 3; a++ {
			b.Lo[a] = min(b.Lo[a], o.Bound.Lo[a])
			b.Hi[a] = max(b.Hi[a], o.Bound.Hi[a])
		}
	}
	return b
}
func area(b Bounds) int64 { d := sub(b.Hi, b.Lo); return d[0]*d[1] + d[1]*d[2] + d[2]*d[0] }
func build(objects []*Object, depth int) *Node {
	if len(objects) == 0 {
		return nil
	}
	node := &Node{Box: union(objects), Depth: depth}
	if len(objects) <= 2 {
		node.Objects = append([]*Object(nil), objects...)
		sort.Slice(node.Objects, func(i, j int) bool { return node.Objects[i].ID < node.Objects[j].ID })
		for _, o := range node.Objects {
			o.LeafDepth = depth
		}
		return node
	}
	var chosen []*Object
	split := 0
	cost := int64(1 << 62)
	for axis := 0; axis < 3; axis++ {
		sorted := append([]*Object(nil), objects...)
		sort.Slice(sorted, func(i, j int) bool {
			a, b := sorted[i], sorted[j]
			ca, cb := floorDiv(a.Bound.Lo[axis]+a.Bound.Hi[axis], 2), floorDiv(b.Bound.Lo[axis]+b.Bound.Hi[axis], 2)
			if ca != cb {
				return ca < cb
			}
			return a.ID < b.ID
		})
		for i := 1; i < len(sorted); i++ {
			c := area(union(sorted[:i]))*int64(i) + area(union(sorted[i:]))*int64(len(sorted)-i)
			if c < cost {
				cost, split, chosen = c, i, sorted
			}
		}
	}
	node.Left, node.Right = build(chosen[:split], depth+1), build(chosen[split:], depth+1)
	return node
}
func (r *Renderer) test(o *Object, ray Ray, kind int) *Hit {
	if r.Active {
		r.ObjectTests[kind]++
	}
	return intersect(o, ray, r.Settings.Epsilon)
}
func (r *Renderer) nodeTest(node *Node, ray Ray, kind int) Slab {
	if r.Active {
		r.NodeTests[kind]++
		node.Visits++
	}
	return slab(node.Box, ray)
}
func (r *Renderer) nearest(ray Ray, kind int) *Hit {
	var found *Hit
	test := func(o *Object) {
		h := r.test(o, ray, kind)
		if h != nil && h.Distance <= r.Settings.Far && (found == nil || h.Distance < found.Distance || (h.Distance == found.Distance && o.ID < found.Object.ID)) {
			found = h
		}
	}
	for _, o := range r.Scene.Objects {
		if o.Kind == "plane" {
			test(o)
		}
	}
	var visit func(*Node)
	visit = func(node *Node) {
		if node == nil {
			return
		}
		s := r.nodeTest(node, ray, kind)
		if !s.Valid || s.Far <= r.Settings.Epsilon || s.Near > r.Settings.Far || (found != nil && s.Near > found.Distance) {
			return
		}
		if node.Left == nil {
			for _, o := range node.Objects {
				test(o)
			}
		} else {
			visit(node.Left)
			visit(node.Right)
		}
	}
	visit(r.Root)
	return found
}
func (r *Renderer) occluders(ray Ray, distance int64) []*Object {
	out := []*Object{}
	test := func(o *Object) {
		if h := r.test(o, ray, 3); h != nil && h.Distance < distance {
			out = append(out, o)
		}
	}
	for _, o := range r.Scene.Objects {
		if o.Kind == "plane" {
			test(o)
		}
	}
	var visit func(*Node)
	visit = func(node *Node) {
		if node == nil {
			return
		}
		s := r.nodeTest(node, ray, 3)
		if !s.Valid || s.Far <= r.Settings.Epsilon || s.Near >= distance {
			return
		}
		if node.Left == nil {
			for _, o := range node.Objects {
				test(o)
			}
		} else {
			visit(node.Left)
			visit(node.Right)
		}
	}
	visit(r.Root)
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out
}
func (r *Renderer) camera(qx, qy int) Ray {
	s, c := r.Settings, r.Scene
	u := floorDiv(int64(qx-2*s.W)*c.HW, int64(2*s.W))
	v := floorDiv(int64(2*s.H-qy)*c.HH, int64(2*s.H))
	return Ray{c.Eye, norm(add(add(c.Forward, scale(c.Right, u)), scale(c.Up, v)))}
}
func (r *Renderer) samples(l *Light, p Vec) []Sample {
	if l.Kind == "sun" {
		return []Sample{{l.Direction, r.Settings.Far, l.Intensity}}
	}
	out := []Sample{}
	k := l.K
	for j := 0; j < k; j++ {
		for i := 0; i < k; i++ {
			q := l.P
			if l.Kind == "area" {
				for a := 0; a < 3; a++ {
					q[a] += floorDiv(int64(2*i+1)*l.U[a], int64(2*k)) + floorDiv(int64(2*j+1)*l.V[a], int64(2*k))
				}
			}
			rel := sub(q, p)
			out = append(out, Sample{norm(rel), length(rel), floorDiv(l.Intensity, int64(k*k))})
		}
	}
	return out
}
func cone(l *Light, d Vec) int64 {
	if l.Kind != "spot" {
		return S
	}
	c := -dot(d, l.Direction)
	if c <= l.Outer {
		return 0
	}
	if c >= l.Inner {
		return S
	}
	return floorDiv((c-l.Outer)*S, l.Inner-l.Outer)
}
func (r *Renderer) local(ray Ray, result *Result, ctx *TraceContext, record *[]string) Vec {
	m := result.Hit.Object.Material
	ds, ss := int64(0), int64(0)
	result.Lit = make([]int, len(r.Scene.Lights))
	for index, l := range r.Scene.Lights {
		lit := 0
		dtotal, stotal := int64(0), int64(0)
		samples := r.samples(l, result.Point)
		for _, sample := range samples {
			if dot(result.Normal, sample.Direction) <= 0 {
				if r.Active {
					l.Backfacing++
				}
				continue
			}
			g := cone(l, sample.Direction)
			if g == 0 {
				if r.Active {
					l.Outside++
				}
				continue
			}
			if r.Active {
				r.Rays[3]++
				l.Shadow++
			}
			if ctx != nil {
				ctx.Rays++
			}
			occluders := r.occluders(Ray{result.Point, sample.Direction}, sample.Distance)
			f := g
			for _, o := range occluders {
				f = mul(f, o.Material.KT)
				if r.Active {
					o.Shadow++
				}
			}
			if f == 0 {
				if r.Active {
					l.Blocked++
				}
				continue
			}
			if len(occluders) > 0 && r.Active {
				l.Attenuated++
			}
			lit++
			dif, spe := components(m, result.Normal, sample.Direction, neg(ray.Direction), mul(sample.Intensity, f))
			dtotal += dif
			stotal += spe
		}
		result.Lit[index] = lit
		if lit > 0 {
			result.Illumination++
		}
		ds += dtotal
		ss += stotal
		if record != nil {
			*record = append(*record, fmt.Sprintf("light %d lit %d of %d diffuse %d specular %d", index+1, lit, len(samples), dtotal, stotal))
		}
	}
	color := Vec{}
	for a, c := range result.Base {
		raw := floorDiv(c*(r.Scene.Ambient+ds), S) + floorDiv(255*ss, S)
		color[a] = min(raw, 255)
		if raw > 255 && r.Active {
			r.Clamped++
		}
	}
	return color
}
func (r *Renderer) trace(ray Ray, kind, depth int, ctx *TraceContext, record *[]string) Result {
	if r.Active {
		r.Rays[kind]++
		r.Depths[depth]++
	}
	if ctx != nil {
		ctx.Rays++
		ctx.Depth = max(ctx.Depth, depth)
	}
	if record != nil {
		*record = append(*record, fmt.Sprintf("ray %s %d origin %s direction %s", rayKinds[kind], depth, ray.Origin, ray.Direction))
	}
	h := r.nearest(ray, kind)
	result := Result{Color: r.Scene.Background, Hit: h}
	if h == nil {
		if r.Active {
			r.Misses[kind]++
		}
		if record != nil {
			*record = append(*record, "miss", fmt.Sprint("color ", result.Color))
		}
		return result
	}
	if r.Active {
		if kind == 0 {
			h.Object.Primary++
		} else {
			h.Object.Secondary++
		}
	}
	result.Point = add(ray.Origin, scale(ray.Direction, h.Distance))
	n0 := outward(h, result.Point, ray.Direction)
	front := dot(n0, ray.Direction) <= 0
	result.Normal = n0
	if !front {
		result.Normal = neg(n0)
	}
	result.Base = baseColor(h.Object.Material, result.Point)
	if record != nil {
		*record = append(*record, fmt.Sprintf("hit %s t %d point %s normal %s base %s", h.Object.Label, h.Distance, result.Point, result.Normal, result.Base))
	}
	color := r.local(ray, &result, ctx, record)
	if record != nil {
		*record = append(*record, fmt.Sprint("local ", color))
	}
	m := h.Object.Material
	if depth < r.Settings.Depth && (m.KR > 0 || m.KT > 0) {
		wr, wt, tdir, tir := refracted(m, ray.Direction, result.Normal, front)
		if tir {
			if r.Active {
				r.TIR++
			}
			if record != nil {
				*record = append(*record, "total_internal_reflection")
			}
		}
		if record != nil {
			*record = append(*record, fmt.Sprintf("weights %d %d %d", S-m.KR-m.KT, wr, wt))
		}
		cr, ct := Vec{}, Vec{}
		if wr > 0 {
			cr = r.trace(Ray{result.Point, reflected(ray.Direction, result.Normal)}, 1, depth+1, ctx, record).Color
		}
		if wt > 0 {
			ct = r.trace(Ray{result.Point, tdir}, 2, depth+1, ctx, record).Color
		}
		color = mix([]Vec{color, cr, ct}, []int64{S - m.KR - m.KT, wr, wt})
	}
	if f := r.Scene.Fog; f != nil {
		fg := int64(0)
		if h.Distance >= f.End {
			fg = S
		} else if h.Distance > f.Start {
			fg = floorDiv((h.Distance-f.Start)*S, f.End-f.Start)
		}
		color = mix([]Vec{color, f.Color}, []int64{S - fg, fg})
	}
	result.Color = color
	if record != nil {
		*record = append(*record, fmt.Sprint("color ", color))
	}
	return result
}
func label(p Pixel) string {
	if p.Center.Hit == nil {
		return "."
	}
	return p.Center.Hit.Object.Label
}
func (r *Renderer) render() {
	s := r.Settings
	r.Pixels = make([]Pixel, s.W*s.H)
	for y := 0; y < s.H; y++ {
		for x := 0; x < s.W; x++ {
			ctx := &TraceContext{}
			v := r.trace(r.camera(4*x+2, 4*y+2), 0, 0, ctx, nil)
			r.Pixels[y*s.W+x] = Pixel{v, v.Color, 1, ctx.Rays, ctx.Depth}
		}
	}
	offsets := [][2]int{{0, -1}, {0, 1}, {-1, 0}, {1, 0}}
	subsamples := [][2]int{{1, 1}, {3, 1}, {1, 3}, {3, 3}}
	for y := 0; y < s.H; y++ {
		for x := 0; x < s.W; x++ {
			index := y*s.W + x
			p := &r.Pixels[index]
			adaptive := false
			for _, d := range offsets {
				xx, yy := x+d[0], y+d[1]
				if xx < 0 || xx >= s.W || yy < 0 || yy >= s.H {
					continue
				}
				q := r.Pixels[yy*s.W+xx]
				contrast := int64(0)
				for a, c := range p.Center.Color {
					contrast = max(contrast, absolute(c-q.Center.Color[a]))
				}
				if label(*p) != label(q) || contrast > int64(s.Contrast) {
					adaptive = true
				}
			}
			if adaptive {
				r.Supersampled++
				p.Samples = 4
				color := Vec{}
				ctx := &TraceContext{Depth: p.Depth}
				for _, d := range subsamples {
					v := r.trace(r.camera(4*x+d[0], 4*y+d[1]), 0, 0, ctx, nil)
					color = add(color, v.Color)
				}
				for a := 0; a < 3; a++ {
					color[a] = floorDiv(color[a], 4)
				}
				p.Color, p.Rays, p.Depth = color, p.Rays+ctx.Rays, ctx.Depth
			}
		}
	}
}
func writeLines(name string, lines []string) {
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	text := ""
	if len(lines) > 0 {
		text = strings.Join(lines, "\n") + "\n"
	}
	if e := os.WriteFile("output/"+name, []byte(text), 0644); e != nil {
		panic(e)
	}
}
func (r *Renderer) images() (int64, int64, int64, bool) {
	s := r.Settings
	tmin, tmax, cmax := int64(1<<62), int64(0), int64(0)
	hit := false
	for _, p := range r.Pixels {
		cmax = max(cmax, p.Rays)
		if p.Center.Hit != nil {
			hit = true
			t := p.Center.Hit.Distance
			tmin, tmax = min(tmin, t), max(tmax, t)
		}
	}
	image, normal, albedo := []string{"P3", fmt.Sprint(s.W, " ", s.H), "255"}, []string{"P3", fmt.Sprint(s.W,
		" ", s.H), "255"}, []string{"P3", fmt.Sprint(s.W, " ", s.H), "255"}
	depth, cost := []string{"P2", fmt.Sprint(s.W, " ", s.H), "255"}, []string{"P2", fmt.Sprint(s.W, " ", s.H), "255"}
	objects, lights, rayDepth := []string{}, []string{}, []string{}
	for y := 0; y < s.H; y++ {
		ic, nc, ac, dc, cc := []string{}, []string{}, []string{}, []string{}, []string{}
		ob, li, rd := "", "", ""
		for x := 0; x < s.W; x++ {
			p := r.Pixels[y*s.W+x]
			ic = append(ic, p.Color.String())
			n, a, d := Vec{}, Vec{}, int64(0)
			if p.Center.Hit != nil {
				a = p.Center.Base
				for axis, v := range p.Center.Normal {
					n[axis] = max(0, min(255, floorDiv((v+S)*255, 2*S)))
				}
				d = 255
				if tmax != tmin {
					d = 255 - floorDiv(235*(p.Center.Hit.Distance-tmin), tmax-tmin)
				}
				li += fmt.Sprint(p.Center.Illumination)
			} else {
				li += "."
			}
			nc = append(nc, n.String())
			ac = append(ac, a.String())
			dc = append(dc, fmt.Sprint(d))
			cc = append(cc, fmt.Sprint(floorDiv(255*p.Rays, cmax)))
			ob += label(p)
			rd += fmt.Sprint(p.Depth)
		}
		image = append(image, strings.Join(ic, " "))
		normal = append(normal, strings.Join(nc, " "))
		albedo = append(albedo, strings.Join(ac, " "))
		depth = append(depth, strings.Join(dc, " "))
		cost = append(cost, strings.Join(cc, " "))
		objects = append(objects, ob)
		lights = append(lights, li)
		rayDepth = append(rayDepth, rd)
	}
	writeLines("image.ppm", image)
	writeLines("normal.ppm", normal)
	writeLines("albedo.ppm", albedo)
	writeLines("depth.pgm", depth)
	writeLines("cost.pgm", cost)
	writeLines("object_map.txt", objects)
	writeLines("light_map.txt", lights)
	writeLines("ray_depth.txt", rayDepth)
	return tmin, tmax, cmax, hit
}
func (r *Renderer) stats(tmin, tmax, cmax int64, hasHit bool) {
	s := r.Settings
	total := int64(0)
	for _, v := range r.Rays {
		total += v
	}
	lines := []string{fmt.Sprint("image ", s.W, " ", s.H), fmt.Sprint("supersampled ", r.Supersampled),
		fmt.Sprintf("rays primary %d reflection %d refraction %d shadow %d total %d", r.Rays[0],
			r.Rays[1], r.Rays[2], r.Rays[3], total), fmt.Sprintf("misses primary %d reflection %d refraction %d",
			r.Misses[0], r.Misses[1], r.Misses[2])}
	d := []string{"depth"}
	for _, v := range r.Depths {
		d = append(d, fmt.Sprint(v))
	}
	lines = append(lines, strings.Join(d, " "))
	for k, name := range rayKinds {
		lines = append(lines, fmt.Sprintf("tests %s nodes %d objects %d", name, r.NodeTests[k], r.ObjectTests[k]))
	}
	lines = append(lines, fmt.Sprint("total_internal_reflection ", r.TIR), fmt.Sprint("clamped ", r.Clamped))
	if hasHit {
		lines = append(lines, fmt.Sprint("distance ", tmin, " ", tmax))
	} else {
		lines = append(lines, "distance none")
	}
	color := Vec{}
	hist := make([]int64, 8)
	for _, p := range r.Pixels {
		color = add(color, p.Color)
		brightness := floorDiv(299*p.Color[0]+587*p.Color[1]+114*p.Color[2], 1000)
		hist[brightness/32]++
	}
	for a := range color {
		color[a] = floorDiv(color[a], int64(len(r.Pixels)))
	}
	lines = append(lines, fmt.Sprint("max_pixel_rays ", cmax), fmt.Sprint("mean ", color))
	h := []string{"histogram"}
	for _, v := range hist {
		h = append(h, fmt.Sprint(v))
	}
	lines = append(lines, strings.Join(h, " "))
	var visit func(*Node)
	visit = func(node *Node) {
		if node == nil {
			return
		}
		kind := "inner"
		if node.Left == nil {
			labels := ""
			for _, o := range node.Objects {
				labels += o.Label
			}
			kind = "leaf " + labels
		}
		lines = append(lines, fmt.Sprintf("node %d %s box %s %s visits %d", node.Depth, kind, node.Box.Lo, node.Box.Hi, node.Visits))
		visit(node.Left)
		visit(node.Right)
	}
	visit(r.Root)
	for _, o := range r.Scene.Objects {
		count := int64(0)
		loX, loY, hiX, hiY := s.W, s.H, -1, -1
		col := Vec{}
		for i, p := range r.Pixels {
			if label(p) == o.Label {
				count++
				x, y := i%s.W, i/s.W
				loX, loY, hiX, hiY = min(loX, x), min(loY, y), max(hiX, x), max(hiY, y)
				col = add(col, p.Color)
			}
		}
		suffix := "box none color none"
		if count > 0 {
			for a := range col {
				col[a] = floorDiv(col[a], count)
			}
			suffix = fmt.Sprintf("box %d %d %d %d color %s", loX, loY, hiX, hiY, col)
		}
		lines = append(lines, fmt.Sprintf("object %s %s primary %d secondary %d shadow %d pixels %d %s",
			o.Label, o.Kind, o.Primary, o.Secondary, o.Shadow, count, suffix))
	}
	for i, l := range r.Scene.Lights {
		count := 0
		for _, p := range r.Pixels {
			if p.Center.Hit != nil && p.Center.Lit[i] > 0 {
				count++
			}
		}
		lines = append(lines, fmt.Sprintf("light %d %s samples %d pixels %d shadow_rays %d blocked %d attenuated %d backfacing %d outside %d",
			i+1, l.Kind, l.K*l.K, count, l.Shadow, l.Blocked, l.Attenuated, l.Backfacing, l.Outside))
	}
	writeLines("stats.txt", lines)
}
func (r *Renderer) queries() {
	r.Active = false
	lines := []string{}
	for index, line := range strings.Split(strings.TrimSuffix(readText("input/queries.txt"), "\n"), "\n") {
		if line == "" {
			continue
		}
		a := strings.Fields(line)
		lines = append(lines, fmt.Sprintf("query %d %s", index+1, line))
		switch a[0] {
		case "pixel":
			v := ints(a[1:])
			p := r.Pixels[int(v[1])*r.Settings.W+int(v[0])]
			distance := "none"
			if p.Center.Hit != nil {
				distance = fmt.Sprint(p.Center.Hit.Distance)
			}
			lines = append(lines, fmt.Sprintf("label %s distance %s color %s samples %d rays %d", label(p), distance, p.Color, p.Samples, p.Rays))
		case "trace":
			v := ints(a[1:])
			r.trace(r.camera(int(4*v[0]+2), int(4*v[1]+2)), 0, 0, nil, &lines)
		case "ray":
			v := ints(a[1:])
			r.trace(Ray{vector(v), norm(vector(v[3:]))}, 0, 0, nil, &lines)
		case "object":
			for _, o := range r.Scene.Objects {
				if o.Label != a[1] {
					continue
				}
				suffix := "bounds none leaf none"
				if o.Kind != "plane" {
					suffix = fmt.Sprintf("bounds %s %s leaf %d", o.Bound.Lo, o.Bound.Hi, o.LeafDepth)
				}
				lines = append(lines, fmt.Sprintf("%s material %s %s", o.Kind, o.Material.Name, suffix))
			}
		case "visible":
			v := ints(a[1:])
			rel := sub(vector(v), r.Scene.Eye)
			ray := Ray{r.Scene.Eye, norm(rel)}
			visible := "yes"
			if len(r.occluders(ray, length(rel)-r.Settings.Epsilon)) > 0 {
				visible = "no"
			}
			h := r.nearest(ray, 0)
			if h == nil {
				lines = append(lines, visible+" first none")
			} else {
				lines = append(lines, fmt.Sprintf("%s first %s t %d", visible, h.Object.Label, h.Distance))
			}
		case "shadow":
			p := vector(ints(a[1:]))
			for i, l := range r.Scene.Lights {
				factor := int64(0)
				set := map[int]bool{}
				for _, sample := range r.samples(l, p) {
					f := cone(l, sample.Direction)
					for _, o := range r.occluders(Ray{p, sample.Direction}, sample.Distance) {
						f = mul(f, o.Material.KT)
						set[o.ID] = true
					}
					factor += f
				}
				labels := ""
				for _, o := range r.Scene.Objects {
					if set[o.ID] {
						labels += o.Label
					}
				}
				if labels == "" {
					labels = "none"
				}
				lines = append(lines, fmt.Sprintf("light %d factor %d occluders %s", i+1, factor, labels))
			}
		case "region":
			v := ints(a[1:])
			count := int64(0)
			color := Vec{}
			labels := map[string]int{}
			for y := int(v[1]); y <= int(v[3]); y++ {
				for x := int(v[0]); x <= int(v[2]); x++ {
					p := r.Pixels[y*r.Settings.W+x]
					count++
					color = add(color, p.Color)
					labels[label(p)]++
				}
			}
			for a := range color {
				color[a] = floorDiv(color[a], count)
			}
			lines = append(lines, fmt.Sprintf("pixels %d mean %s", count, color))
			ordered := []string{}
			for _, o := range r.Scene.Objects {
				ordered = append(ordered, o.Label)
			}
			ordered = append(ordered, ".")
			for _, label := range ordered {
				if labels[label] > 0 {
					lines = append(lines, fmt.Sprintf("label %s %d", label, labels[label]))
				}
			}
		}
	}
	writeLines("queries.txt", lines)
}
func main() {
	scene, settings := readScene(), readSettings()
	bounded := []*Object{}
	for _, o := range scene.Objects {
		if o.Kind != "plane" {
			o.Bound = bounding(o, settings.Pad)
			bounded = append(bounded, o)
		}
	}
	r := Renderer{Scene: scene, Settings: settings, Root: build(bounded, 0), Active: true, Depths: make([]int64, settings.Depth+1)}
	r.render()
	tmin, tmax, cmax, hit := r.images()
	r.stats(tmin, tmax, cmax, hit)
	r.queries()
}
