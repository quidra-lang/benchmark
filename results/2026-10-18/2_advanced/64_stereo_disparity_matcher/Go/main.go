package main

import (
	"fmt"
	"sort"
	"strings"
)

var methodNames = []string{"sad", "ssd", "census", "sgm", "fusion", "wta_final", "sgm_final"}
var sourceNames = []string{"kept", "median", "background", "interpolated", "none"}

type Selection struct {
	Image, Reasons []int
	Margins        []int64
	LR             [4]int
	Bounds, Window int
}
type Post struct {
	Image, Source                                              []int
	Components, Pixels, Median, Background, Interpolated, None int
}
type Method struct {
	Name      string
	Image     []int
	Selection *Selection
	Post      *Post
}
type Application struct {
	Left, Right, Truth      Image
	Params                  Params
	Regions                 Regions
	Texture                 []int64
	CensusLeft, CensusRight []uint32
	Methods                 []Method
	Aggregate               Volume
	Report                  []string
}

func countTrue(v []bool) int {
	n := 0
	for _, b := range v {
		if b {
			n++
		}
	}
	return n
}
func validCount(v []int) int {
	n := 0
	for _, x := range v {
		if x != 0 {
			n++
		}
	}
	return n
}
func lowerMedian(v []int) int { a := append([]int(nil), v...); sort.Ints(a); return a[(len(a)-1)/2] }
func abs64(v int64) int64 {
	if v < 0 {
		return -v
	}
	return v
}
func (a *Application) selectDisparity(v Volume, window int) *Selection {
	p := a.Params
	w, h := a.Left.W, a.Left.H
	n := w * h
	right := make([]int, n)
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			best := int64(0)
			for d := p.Min; d <= p.Max && x+d < w; d++ {
				cost := v[y*w+x+d][d-p.Min]
				if right[y*w+x] == 0 || cost < best {
					best = cost
					right[y*w+x] = d
				}
			}
		}
	}
	out := &Selection{Image: make([]int, n), Reasons: make([]int, n), Margins: make([]int64, n), Window: window}
	for index, row := range v {
		x := index % w
		di := 0
		for j := 1; j < len(row); j++ {
			if row[j] < row[di] {
				di = j
			}
		}
		d1, c1 := p.Min+di, row[di]
		c2 := int64(1 << 62)
		for j, cost := range row {
			if absolute(j-di) >= 2 {
				c2 = min(c2, cost)
			}
		}
		if d1 == p.Min || d1 == p.Max {
			out.Bounds++
		}
		consistent := func(d int) bool { return x-d >= 0 && absolute(d-right[index-d]) <= p.LR }
		reason := 0
		if a.Texture[index] < p.TextureThreshold {
			reason = 50
		} else if 100*c2 <= (100+p.Uniqueness)*c1 {
			reason = 100
		} else if x-d1 < 0 {
			reason = 150
		} else if !consistent(d1) {
			reason = 255
			for d := p.Min; d <= p.Max; d++ {
				if consistent(d) {
					reason = 200
					break
				}
			}
		}
		out.Reasons[index] = reason
		if reason == 0 {
			out.Image[index] = d1
			out.Margins[index] = c2 - c1
		}
		if reason == 0 || reason == 200 || reason == 255 {
			diff := absolute(d1 - right[index-d1])
			out.LR[min(3, diff)]++
		}
	}
	return out
}
func components(image []int, w, h, span int) [][]int {
	visited := make([]bool, len(image))
	out := [][]int{}
	neighbors := [][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}
	for root, value := range image {
		if value == 0 || visited[root] {
			continue
		}
		visited[root] = true
		queue := []int{root}
		for head := 0; head < len(queue); head++ {
			p := queue[head]
			x, y := p%w, p/w
			for _, d := range neighbors {
				xx, yy := x+d[0], y+d[1]
				if xx < 0 || xx >= w || yy < 0 || yy >= h {
					continue
				}
				q := yy*w + xx
				if image[q] != 0 && !visited[q] && absolute(image[p]-image[q]) <= span {
					visited[q] = true
					queue = append(queue, q)
				}
			}
		}
		out = append(out, queue)
	}
	return out
}
func (a *Application) postprocess(selection *Selection) *Post {
	p := a.Params
	w, h := a.Left.W, a.Left.H
	a0 := selection.Image
	a1 := append([]int(nil), a0...)
	out := &Post{Source: make([]int, len(a0))}
	for _, component := range components(a0, w, h, p.SpeckleRange) {
		if len(component) < p.SpeckleSize {
			out.Components++
			out.Pixels += len(component)
			for _, i := range component {
				a1[i] = 0
			}
		}
	}
	a2 := make([]int, len(a0))
	for i, d := range a1 {
		if d == 0 {
			continue
		}
		x, y := i%w, i/w
		values := []int{}
		for yy := max(0, y-1); yy <= min(h-1, y+1); yy++ {
			for xx := max(0, x-1); xx <= min(w-1, x+1); xx++ {
				if v := a1[yy*w+xx]; v != 0 {
					values = append(values, v)
				}
			}
		}
		a2[i] = lowerMedian(values)
		if a2[i] != a1[i] {
			out.Median++
		}
	}
	out.Image = append([]int(nil), a2...)
	for i, d := range a2 {
		if d != 0 {
			if d == a0[i] {
				out.Source[i] = 0
			} else {
				out.Source[i] = 1
			}
			continue
		}
		out.Source[i] = 4
		x, y := i%w, i/w
		values := []int{}
		background := selection.Reasons[i] == 150 || selection.Reasons[i] == 255
		if background {
			for xx := x - 1; xx >= 0; xx-- {
				if v := a2[y*w+xx]; v != 0 {
					values = append(values, v)
					break
				}
			}
			for xx := x + 1; xx < w; xx++ {
				if v := a2[y*w+xx]; v != 0 {
					values = append(values, v)
					break
				}
			}
			if len(values) > 0 {
				v := values[0]
				for _, d := range values[1:] {
					v = min(v, d)
				}
				out.Image[i] = v
				out.Source[i] = 2
				out.Background++
			}
		} else {
			for _, r := range directions {
				for xx, yy := x+r[0], y+r[1]; xx >= 0 && xx < w && yy >= 0 && yy < h; xx, yy = xx+r[0], yy+r[1] {
					if v := a2[yy*w+xx]; v != 0 {
						values = append(values, v)
						break
					}
				}
			}
			if len(values) > 0 {
				out.Image[i] = lowerMedian(values)
				out.Source[i] = 3
				out.Interpolated++
			}
		}
		if out.Image[i] == 0 {
			out.None++
		}
	}
	return out
}
func (a *Application) prepare() {
	p := a.Params
	a.Regions = truthRegions(a.Truth)
	a.Texture = texture(a.Left, p.TextureWindow)
	a.CensusLeft, a.CensusRight = census(a.Left), census(a.Right)
	chosen := map[string]*Selection{}
	sweep := []string{}
	for _, kind := range methodNames[:3] {
		var best Metrics
		for i, window := range p.Windows[kind] {
			cost := costVolume(a.Left, a.Right, a.CensusLeft, a.CensusRight, kind, window, p)
			selection := a.selectDisparity(cost, window)
			metrics := evaluate(selection.Image, a.Truth.Pixels, a.Regions.Nonocc)
			sweep = append(sweep, fmt.Sprintf("sweep %s window %d valid %d bad1 %s bad2 %s", kind, window,
				validCount(selection.Image), ratio(int64(metrics.Bad1), int64(metrics.Pixels)), ratio(int64(metrics.Bad2),
					int64(metrics.Pixels))))
			if i == 0 || metrics.Bad1 < best.Bad1 || (metrics.Bad1 == best.Bad1 && metrics.Bad2 < best.Bad2) {
				chosen[kind] = selection
				best = metrics
			}
		}
	}
	base := costVolume(a.Left, a.Right, a.CensusLeft, a.CensusRight, p.SGMCost, p.SGMWindow, p)
	paths := []string{}
	a.Aggregate = aggregate(base, a.Left, p, func(i int, summed Volume) {
		selection := a.selectDisparity(summed, p.SGMWindow)
		chosen["sgm"] = selection
		metrics := evaluate(selection.Image, a.Truth.Pixels, a.Regions.Nonocc)
		paths = append(paths, fmt.Sprintf("paths %d valid %d bad1 %s bad2 %s", i, validCount(selection.Image),
			ratio(int64(metrics.Bad1), int64(metrics.Pixels)), ratio(int64(metrics.Bad2), int64(metrics.Pixels))))
	})
	for _, kind := range methodNames[:4] {
		a.Methods = append(a.Methods, Method{Name: kind, Image: chosen[kind].Image, Selection: chosen[kind]})
	}
	fusion := make([]int, len(a.Left.Pixels))
	for i := range fusion {
		values := []int{}
		for _, kind := range methodNames[:4] {
			if d := chosen[kind].Image[i]; d != 0 {
				values = append(values, d)
			}
		}
		if len(values) > 0 {
			median := lowerMedian(values)
			votes := 0
			for _, d := range values {
				if absolute(d-median) <= 1 {
					votes++
				}
			}
			if votes >= p.FusionVotes {
				fusion[i] = median
			}
		}
	}
	a.Methods = append(a.Methods, Method{Name: "fusion", Image: fusion})
	wtaPost, sgmPost := a.postprocess(chosen[p.WTACost]), a.postprocess(chosen["sgm"])
	a.Methods = append(a.Methods, Method{Name: "wta_final", Image: wtaPost.Image, Post: wtaPost}, Method{Name: "sgm_final", Image: sgmPost.Image, Post: sgmPost})
	a.Report = append(a.Report, sweep...)
	a.Report = append(a.Report, paths...)
}
func (a *Application) imagesAndDepth() {
	p := a.Params
	w, h := a.Left.W, a.Left.H
	for _, which := range []struct {
		Index int
		Name  string
	}{{5, "disparity_wta.pgm"}, {6, "disparity_sgm.pgm"}} {
		pixels := make([]int, w*h)
		for i, d := range a.Methods[which.Index].Image {
			pixels[i] = 8 * d
		}
		writePGM(which.Name, w, h, pixels)
	}
	writePGM("occlusion.pgm", w, h, a.Methods[3].Selection.Reasons)
	errors := make([]int, w*h)
	for i, g := range a.Truth.Pixels {
		if g == 0 {
			continue
		}
		d := a.Methods[6].Image[i]
		if d == 0 {
			errors[i] = 255
		} else {
			errors[i] = 50 * (1 + min(3, absolute(d-g)))
		}
	}
	writePGM("error_sgm.pgm", w, h, errors)
	out := []string{"x,y,sad,ssd,census,sgm,disparity,source,subpixel,depth,truth,truth_depth"}
	for _, sample := range p.Samples {
		x, y := sample[0], sample[1]
		index := y*w + x
		row := []string{fmt.Sprint(x), fmt.Sprint(y)}
		for _, method := range a.Methods[:4] {
			v := "-"
			if d := method.Image[index]; d != 0 {
				v = fmt.Sprint(d)
			}
			row = append(row, v)
		}
		d := a.Methods[6].Image[index]
		if d == 0 {
			row = append(row, "-", "none", "-", "-")
		} else {
			sub, depth := subpixel(a.Aggregate[index], d, p)
			row = append(row, fmt.Sprint(d), sourceNames[a.Methods[6].Post.Source[index]], sub, depth)
		}
		g := a.Truth.Pixels[index]
		if g == 0 {
			row = append(row, "-", "-")
		} else {
			row = append(row, fmt.Sprint(g), decimal2(p.Focal*p.Baseline, int64(g)))
		}
		out = append(out, strings.Join(row, ","))
	}
	writeLines("depth.csv", out)
}

type Object struct {
	Pixels                                              []int
	X0, Y0, X1, Y1, Min, Max, Median, Truth, TruthCount int
	Sum                                                 int64
	First                                               int
}

func (a *Application) objects() {
	p := a.Params
	w, h := a.Left.W, a.Left.H
	image := a.Methods[6].Image
	objects := []Object{}
	small, pixels := 0, 0
	for _, component := range components(image, w, h, p.ObjectRange) {
		if len(component) < p.ObjectSize {
			small++
			continue
		}
		o := Object{Pixels: component, X0: w, Y0: h, X1: -1, Y1: -1, First: component[0]}
		values := []int{}
		counts := map[int]int{}
		for _, index := range component {
			x, y := index%w, index/w
			o.X0, o.Y0, o.X1, o.Y1 = min(o.X0, x), min(o.Y0, y), max(o.X1, x), max(o.Y1, y)
			d := image[index]
			o.Sum += int64(d)
			values = append(values, d)
			if g := a.Truth.Pixels[index]; g != 0 {
				counts[g]++
			}
		}
		sort.Ints(values)
		o.Min, o.Max, o.Median = values[0], values[len(values)-1], values[(len(values)-1)/2]
		for _, g := range a.Regions.Layers {
			if counts[g] > o.TruthCount {
				o.Truth, o.TruthCount = g, counts[g]
			}
		}
		objects = append(objects, o)
		pixels += len(component)
	}
	sort.Slice(objects, func(i, j int) bool {
		x, y := objects[i], objects[j]
		if x.Median != y.Median {
			return x.Median > y.Median
		}
		if len(x.Pixels) != len(y.Pixels) {
			return len(x.Pixels) > len(y.Pixels)
		}
		return x.First < y.First
	})
	out := []string{fmt.Sprintf("objects %d small %d pixels %d", len(objects), small, pixels)}
	detected := map[int]bool{}
	for rank, o := range objects {
		n := len(o.Pixels)
		truth := "truth - iou -"
		if o.Truth != 0 {
			union := n + a.Regions.LayerCounts[o.Truth] - o.TruthCount
			truth = fmt.Sprintf("truth %d iou %s", o.Truth, ratio(int64(o.TruthCount), int64(union)))
			if 2*o.TruthCount > union {
				detected[o.Truth] = true
			}
		}
		out = append(out, fmt.Sprintf("object %d pixels %d box %d %d %d %d disparity %d %d median %d mean %s depth %s size %s %s %s",
			rank+1, n, o.X0, o.Y0, o.X1, o.Y1, o.Min, o.Max, o.Median, decimal2(o.Sum, int64(n)),
			decimal2(p.Focal*p.Baseline*int64(n), o.Sum), decimal2(int64(o.X1-o.X0+1)*p.Baseline,
				int64(o.Median)), decimal2(int64(o.Y1-o.Y0+1)*p.Baseline, int64(o.Median)), truth))
	}
	missed := []string{}
	for _, g := range a.Regions.Layers {
		if !detected[g] {
			missed = append(missed, fmt.Sprint(g))
		}
	}
	if len(missed) == 0 {
		missed = append(missed, "-")
	}
	out = append(out, fmt.Sprintf("layers %d detected %d missed %s", len(a.Regions.Layers), len(detected), strings.Join(missed, " ")))
	writeLines("objects.txt", out)
}
func imageSummary(img Image) string {
	total := int64(0)
	lo, hi := img.Pixels[0], img.Pixels[0]
	for _, v := range img.Pixels {
		total += int64(v)
		lo, hi = min(lo, v), max(hi, v)
	}
	return fmt.Sprintf("mean %s min %d max %d", decimal2(total, int64(len(img.Pixels))), lo, hi)
}
func (a *Application) evaluationReport() {
	p := a.Params
	w, h := a.Left.W, a.Left.H
	n := w * h
	textureSum := int64(0)
	textureless := 0
	for _, t := range a.Texture {
		textureSum += t
		if t < p.TextureThreshold {
			textureless++
		}
	}
	known, nonocc, occluded, disc := countTrue(a.Regions.Known), countTrue(a.Regions.Nonocc), countTrue(a.Regions.Occluded), countTrue(a.Regions.Disc)
	difference, absoluteDifference := int64(0), int64(0)
	for index, inside := range a.Regions.Nonocc {
		if inside {
			g := a.Truth.Pixels[index]
			delta := int64(a.Right.Pixels[index-g] - a.Left.Pixels[index])
			difference += delta
			absoluteDifference += abs64(delta)
		}
	}
	bias := decimal2(abs64(difference), int64(nonocc))
	if difference < 0 && bias != "0.00" {
		bias = "-" + bias
	}
	out := []string{fmt.Sprint("image ", w, " ", h), fmt.Sprint("disparities ", p.Min, " ", p.Max), "left " + imageSummary(a.Left),
		"right " + imageSummary(a.Right), fmt.Sprintf("texture mean %s textureless %d", decimal2(textureSum,
			int64(n)), textureless), fmt.Sprintf("ground_truth known %d nonocc %d occluded %d disc %d unknown %d",
			known, nonocc, occluded, disc, n-known), fmt.Sprintf("photometric pixels %d mean_abs %s bias %s",
			nonocc, decimal2(absoluteDifference, int64(nonocc)), bias)}
	out = append(out, a.Report...)
	masks := [][]bool{a.Regions.Nonocc, a.Regions.Known, a.Regions.Disc}
	regionNames := []string{"nonocc", "all", "disc"}
	metrics := make([][]Metrics, len(a.Methods))
	for mi, method := range a.Methods {
		valid := validCount(method.Image)
		out = append(out, fmt.Sprintf("method %s valid %d invalid %d", method.Name, valid, n-valid))
		values := []int{}
		distinct := map[int]bool{}
		horizontal, vertical := 0, 0
		for index, d := range method.Image {
			if d == 0 {
				continue
			}
			values = append(values, d)
			distinct[d] = true
			x, y := index%w, index/w
			if x+1 < w && method.Image[index+1] != 0 && absolute(d-method.Image[index+1]) >= 2 {
				horizontal++
			}
			if y+1 < h && method.Image[index+w] != 0 && absolute(d-method.Image[index+w]) >= 2 {
				vertical++
			}
		}
		if len(values) == 0 {
			out = append(out, "disparity min - max - median - distinct 0")
		} else {
			sort.Ints(values)
			out = append(out, fmt.Sprintf("disparity min %d max %d median %d distinct %d", values[0], values[len(values)-1], values[(len(values)-1)/2], len(distinct)))
		}
		out = append(out, fmt.Sprintf("jumps horizontal %d vertical %d", horizontal, vertical))
		if method.Selection != nil {
			s := method.Selection
			counts := map[int]int{}
			for _, reason := range s.Reasons {
				counts[reason]++
			}
			out = append(out, fmt.Sprintf("window %d bounds %d", s.Window, s.Bounds), fmt.Sprintf("reasons textureless %d nonunique %d outside %d mismatch %d occluded %d",
				counts[50], counts[100], counts[150], counts[200], counts[255]), fmt.Sprintf("lr 0 %d 1 %d 2 %d 3+ %d",
				s.LR[0], s.LR[1], s.LR[2], s.LR[3]))
		} else if method.Name == "fusion" {
			counts := [5]int{}
			for index := range method.Image {
				count := 0
				for _, m := range a.Methods[:4] {
					if m.Image[index] != 0 {
						count++
					}
				}
				counts[count]++
			}
			out = append(out, fmt.Sprintf("votes 0 %d 1 %d 2 %d 3 %d 4 %d", counts[0], counts[1], counts[2], counts[3], counts[4]))
		} else {
			post := method.Post
			out = append(out, fmt.Sprintf("postprocess speckles %d %d median %d background %d interpolated %d unfilled %d",
				post.Components, post.Pixels, post.Median, post.Background, post.Interpolated, post.None))
			for source, name := range sourceNames {
				mask := make([]bool, n)
				for i, known := range a.Regions.Known {
					mask[i] = known && post.Source[i] == source
				}
				m := evaluate(method.Image, a.Truth.Pixels, mask)
				out = append(out, fmt.Sprintf("source %s pixels %d bad1 %s", name, m.Pixels, ratio(int64(m.Bad1), int64(m.Pixels))))
			}
		}
		for region, mask := range masks {
			m := evaluate(method.Image, a.Truth.Pixels, mask)
			metrics[mi] = append(metrics[mi], m)
			mae := "-"
			if m.Valid > 0 {
				mae = decimal2(m.Error, int64(m.Valid))
			}
			out = append(out, fmt.Sprintf("region %s pixels %d valid %d bad1 %s bad2 %s mae %s exact %d", regionNames[region],
				m.Pixels, m.Valid, ratio(int64(m.Bad1), int64(m.Pixels)), ratio(int64(m.Bad2), int64(m.Pixels)),
				mae, m.Exact))
		}
		depthCount := 0
		depthSum, depthMax := int64(0), int64(0)
		for i, inside := range a.Regions.Nonocc {
			if inside && method.Image[i] != 0 {
				error := abs64(depthHundred(method.Image[i], p) - depthHundred(a.Truth.Pixels[i], p))
				depthCount++
				depthSum += error
				depthMax = max(depthMax, error)
			}
		}
		if depthCount == 0 {
			out = append(out, "depth_error pixels 0 mean - max -")
		} else {
			out = append(out, fmt.Sprintf("depth_error pixels %d mean %s max %s", depthCount, decimal2(depthSum, int64(100*depthCount)), decimal2(depthMax, 100)))
		}
		errors := [5]int{}
		invalid := 0
		for i, known := range a.Regions.Known {
			if !known {
				continue
			}
			d := method.Image[i]
			if d == 0 {
				invalid++
			} else {
				errors[min(4, absolute(d-a.Truth.Pixels[i]))]++
			}
		}
		out = append(out, fmt.Sprintf("errors 0 %d 1 %d 2 %d 3 %d 4+ %d invalid %d", errors[0], errors[1], errors[2], errors[3], errors[4], invalid))
	}
	for region, name := range regionNames {
		order := []int{0, 1, 2, 3, 4, 5, 6}
		sort.Slice(order, func(i, j int) bool {
			a, b := metrics[order[i]][region], metrics[order[j]][region]
			if a.Bad1 != b.Bad1 {
				return a.Bad1 < b.Bad1
			}
			if a.Bad2 != b.Bad2 {
				return a.Bad2 < b.Bad2
			}
			if a.Valid == 0 || b.Valid == 0 {
				if a.Valid == 0 && b.Valid > 0 {
					return false
				}
				if a.Valid > 0 && b.Valid == 0 {
					return true
				}
			} else {
				x, y := a.Error*int64(b.Valid), b.Error*int64(a.Valid)
				if x != y {
					return x < y
				}
			}
			return order[i] < order[j]
		})
		line := []string{"ranking", name}
		for _, index := range order {
			line = append(line, a.Methods[index].Name)
		}
		out = append(out, strings.Join(line, " "))
	}
	for _, method := range a.Methods[:4] {
		tp, fp, fn := 0, 0, 0
		for i, reason := range method.Selection.Reasons {
			detected := reason == 150 || reason == 255
			if a.Regions.Occluded[i] {
				if detected {
					tp++
				} else {
					fn++
				}
			} else if a.Regions.Nonocc[i] && detected {
				fp++
			}
		}
		out = append(out, fmt.Sprintf("occlusion %s tp %d fp %d fn %d precision %s recall %s", method.Name,
			tp, fp, fn, ratio(int64(tp), int64(tp+fp)), ratio(int64(tp), int64(tp+fn))))
	}
	for _, method := range a.Methods[:4] {
		indices := []int{}
		for i, inside := range a.Regions.Nonocc {
			if inside && method.Image[i] != 0 {
				indices = append(indices, i)
			}
		}
		sort.Slice(indices, func(i, j int) bool {
			x, y := method.Selection.Margins[indices[i]], method.Selection.Margins[indices[j]]
			if x != y {
				return x > y
			}
			return indices[i] < indices[j]
		})
		for _, percent := range []int{25, 50, 75, 100} {
			count := (len(indices)*percent + 99) / 100
			bad := 0
			for _, i := range indices[:count] {
				if absolute(method.Image[i]-a.Truth.Pixels[i]) > 1 {
					bad++
				}
			}
			margin := "-"
			if count > 0 {
				margin = fmt.Sprint(method.Selection.Margins[indices[count-1]])
			}
			out = append(out, fmt.Sprintf("confidence %s %d pixels %d margin %s bad1 %s", method.Name, percent, count, margin, ratio(int64(bad), int64(count))))
		}
	}
	for _, g := range a.Regions.Layers {
		mask := make([]bool, n)
		for i, v := range a.Truth.Pixels {
			mask[i] = v == g && a.Regions.Nonocc[i]
		}
		line := []string{fmt.Sprintf("layer %d pixels %d nonocc %d bad1", g, a.Regions.LayerCounts[g], countTrue(mask))}
		for _, method := range a.Methods {
			m := evaluate(method.Image, a.Truth.Pixels, mask)
			line = append(line, fmt.Sprint(m.Bad1))
		}
		out = append(out, strings.Join(line, " "))
	}
	hist := map[int]int{}
	for _, d := range a.Methods[6].Image {
		if d != 0 {
			hist[d]++
		}
	}
	for d := p.Min; d <= p.Max; d++ {
		out = append(out, fmt.Sprintf("histogram %d %d", d, hist[d]))
	}
	writeLines("evaluation.txt", out)
}
func main() {
	a := Application{Left: readPGM("input/left.pgm"), Right: readPGM("input/right.pgm"), Truth: readPGM("input/ground_truth.pgm"), Params: readParams()}
	a.prepare()
	a.imagesAndDepth()
	a.evaluationReport()
	a.objects()
}
