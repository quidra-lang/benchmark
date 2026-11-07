package main

import (
	"fmt"
	"math"
	"os"
	"sort"
	"strings"
)

type Component struct{ ID, H, V, Tq, Td, Ta int }
type Geometry struct {
	W, H, Hmax, Vmax, MX, MY, Restart int
	Components                        [3]Component
}
type Block struct {
	MCU, K, BX, BY int
	Z              [64]int
	Diff, Bits     int
}
type Symbol struct{ Table, Value, Extra, N int }
type Interval struct {
	First, Count, Position, Length int
	State                          string
}
type Encoding struct {
	G         Geometry
	Quant     [2][64]int
	Tables    [4]Huffman
	Counts    [4][256]int
	Blocks    []Block
	Intervals []Interval
	Bytes     []byte
	Header,
	Scan, Padding, Stuffed int
	Source [3]Plane
}
type Segment struct {
	Position, Length int
	Name             string
}
type Decoding struct {
	G         Geometry
	Quant     map[int][64]int
	Tables    map[int]Huffman
	Blocks    []Block
	Intervals []Interval
	Segments  []Segment
	Planes,
	Full [3]Plane
	Image Image
	Scan  int
}

func geometry(w, h, ri int, c [3]Component) Geometry {
	g := Geometry{W: w, H: h, Restart: ri, Components: c}
	for _, v := range c {
		g.Hmax = max(g.Hmax, v.H)
		g.Vmax = max(g.Vmax, v.V)
	}
	g.MX = (w + 8*g.Hmax - 1) / (8 * g.Hmax)
	g.MY = (h + 8*g.Vmax - 1) / (8 * g.Vmax)
	return g
}
func encodeGeometry(im Image, s string, ri int) Geometry {
	h, v := 1, 1
	if s != "444" {
		h = 2
	}
	if s == "420" {
		v = 2
	}
	return geometry(im.W,
		im.H, ri, [3]Component{{1, h, v, 0, 0, 0}, {2, 1, 1, 1, 1, 1}, {3, 1, 1, 1, 1, 1}})
}
func blockOrder(g Geometry) []Block {
	var b []Block
	for m := 0; m < g.MX*g.MY; m++ {
		for k, c := range g.Components {
			for v := 0; v < c.V; v++ {
				for h := 0; h < c.H; h++ {
					b = append(b,
						Block{MCU: m, K: k, BX: c.H*(m%g.MX) + h, BY: c.V*(m/g.MX) + v})
				}
			}
		}
	}
	return b
}
func intervalOrder(g Geometry) []Interval {
	n := g.MX * g.MY
	ri := g.Restart
	if ri == 0 {
		ri = n
	}
	var a []Interval
	for first := 0; first < n; first += ri {
		a = append(a,
			Interval{First: first, Count: min(ri, n-first), State: "lost"})
	}
	return a
}
func blockPixels(p Plane, b Block) [64]int {
	var a [64]int
	for y := 0; y < 8; y++ {
		copy(a[y*8:], p.A[(8*b.BY+y)*p.W+8*b.BX:(8*b.BY+y)*p.W+8*b.BX+8])
	}
	return a
}
func symbols(z [64]int, diff, k int) []Symbol {
	t := 0
	if k > 0 {
		t = 2
	}
	n := category(diff)
	a := []Symbol{{t, n,
		extra(diff), n}}
	run := 0
	for i := 1; i < 64; i++ {
		v := z[i]
		if v == 0 {
			run++
			continue
		}
		for run >= 16 {
			a = append(a,
				Symbol{Table: t + 1, Value: 240})
			run -= 16
		}
		n = category(v)
		a = append(a, Symbol{t + 1, 16*run + n, extra(v), n})
		run = 0
	}
	if run > 0 {
		a = append(a,
			Symbol{Table: t + 1})
	}
	return a
}
func word(b []byte, v int) []byte { return append(b, byte(v>>8), byte(v)) }
func segment(b []byte, marker int, contents []byte) []byte {
	b = append(b, 255, byte(marker))
	b = word(b, len(contents)+2)
	return append(b, contents...)
}
func assembleHeader(g Geometry, q [2][64]int, t [4]Huffman) []byte {
	b := []byte{255, 216}
	var a []byte
	for k := 0; k < 2; k++ {
		a = append(a,
			byte(k))
		for _, v := range ordered(q[k]) {
			a = append(a, byte(v))
		}
	}
	b = segment(b, 219, a)
	a = []byte{8}
	a = word(a,
		g.H)
	a = word(a, g.W)
	a = append(a, 3)
	for _, c := range g.Components {
		a = append(a, byte(c.ID), byte(16*c.H+c.V),
			byte(c.Tq))
	}
	b = segment(b, 192, a)
	a = nil
	for k := 0; k < 4; k++ {
		a = append(a, byte((k%2)*16+k/2))
		for l := 1; l <= 16; l++ {
			a = append(a,
				byte(t[k].Bits[l]))
		}
		for _, v := range t[k].Values {
			a = append(a, byte(v))
		}
	}
	b = segment(b, 196, a)
	if g.Restart > 0 {
		b = segment(b,
			221, word(nil, g.Restart))
	}
	a = []byte{3}
	for _, c := range g.Components {
		a = append(a, byte(c.ID), byte(16*c.Td+c.Ta))
	}
	a = append(a,
		0, 63, 0)
	return segment(b, 218, a)
}
func encodeCoefficients(g Geometry, q [2][64]int, blocks []Block, mode string, standard [4]Huffman) Encoding {
	e := Encoding{G: g,
		Quant: q, Blocks: append([]Block(nil), blocks...), Intervals: intervalOrder(g)}
	seq := make([][]Symbol,
		len(blocks))
	pred := [3]int{}
	lastInterval := -1
	ri := g.Restart
	if ri == 0 {
		ri = g.MX * g.MY
	}
	for i, b := range e.Blocks {
		j := b.MCU / ri
		if j != lastInterval {
			pred = [3]int{}
			lastInterval = j
		}
		e.Blocks[i].Diff = b.Z[0] - pred[b.K]
		pred[b.K] = b.Z[0]
		seq[i] = symbols(b.Z,
			e.Blocks[i].Diff, b.K)
		for _, s := range seq[i] {
			e.Counts[s.Table][s.Value]++
		}
	}
	e.Tables = standard
	if mode == "optimized" {
		for k := 0; k < 4; k++ {
			e.Tables[k] = optimized(e.Counts[k])
		}
	}
	head := assembleHeader(g,
		q, e.Tables)
	e.Header = len(head)
	w := BitWriter{Bytes: append([]byte(nil), head...)}
	lastInterval = -1
	for i, b := range e.Blocks {
		j := b.MCU / ri
		if j != lastInterval {
			if lastInterval >= 0 {
				w.Pad()
				e.Intervals[lastInterval].Length = len(w.Bytes) - e.Intervals[lastInterval].Position
				w.Marker(208 + (lastInterval % 8))
			}
			e.Intervals[j].Position = len(w.Bytes)
			lastInterval = j
		}
		for _, s := range seq[i] {
			t := e.Tables[s.Table]
			w.Write(t.Code[s.Value], t.Length[s.Value])
			w.Write(s.Extra,
				s.N)
			e.Blocks[i].Bits += t.Length[s.Value] + s.N
		}
	}
	w.Pad()
	e.Intervals[lastInterval].Length = len(w.Bytes) - e.Intervals[lastInterval].Position
	e.Scan = len(w.Bytes) - e.Header
	e.Padding,
		e.Stuffed = w.Padding, w.Stuffed
	e.Bytes = append(w.Bytes, 255, 217)
	return e
}
func encode(im Image, q int, s, mode string, ri int, t InputTables) Encoding {
	g := encodeGeometry(im, s, ri)
	p := componentPlanes(im,
		g)
	qt := quantTables(t.Base, q)
	b := blockOrder(g)
	for i, v := range b {
		b[i].Z = quantize(transform(blockPixels(p[v.K],
			v), t.C), qt[g.Components[v.K].Tq])
	}
	e := encodeCoefficients(g, qt, b, mode, t.Standard)
	e.Source = p
	return e
}
func makePlanes(g Geometry, b []Block, q map[int][64]int, c [64]int) [3]Plane {
	var p [3]Plane
	for k, v := range g.Components {
		p[k] = newPlane(8*v.H*g.MX, 8*v.V*g.MY)
	}
	for _, v := range b {
		a := reconstruct(v.Z,
			q[g.Components[v.K].Tq], c)
		for y := 0; y < 8; y++ {
			copy(p[v.K].A[(8*v.BY+y)*p[v.K].W+8*v.BX:], a[y*8:(y+1)*8])
		}
	}
	return p
}
func readWord(b []byte, p int) int { return 256*int(b[p]) + int(b[p+1]) }
func decode(b []byte, c [64]int) Decoding {
	d := Decoding{Quant: map[int][64]int{}, Tables: map[int]Huffman{},
		Segments: []Segment{{0, 0, "SOI"}}}
	p, ri, w, h := 2, 0, 0, 0
	var components [3]Component
	for {
		m := int(b[p+1])
		ls := readWord(b,
			p+2)
		a := b[p+4 : p+ls+2]
		name := ""
		switch {
		case m >= 224 && m <= 239:
			name = fmt.Sprintf("APP%d", m-224)
		case m == 254:
			name = "COM"
		case m == 219:
			name = "DQT"
			for j := 0; j < len(a); j += 65 {
				var q [64]int
				for k, i := range zigzag() {
					q[i] = int(a[j+1+k])
				}
				d.Quant[int(a[j])] = q
			}
		case m == 196:
			name = "DHT"
			for j := 0; j < len(a); {
				key := 4*int(a[j]>>4) + int(a[j]&15)
				j++
				var t Huffman
				n := 0
				for l := 1; l <= 16; l++ {
					t.Bits[l] = int(a[j])
					j++
					n += t.Bits[l]
				}
				for k := 0; k < n; k++ {
					t.Values = append(t.Values,
						int(a[j+k]))
				}
				j += n
				t.Assign()
				d.Tables[key] = t
			}
		case m == 192:
			name = "SOF0"
			h, w = readWord(a, 1), readWord(a,
				3)
			for k := 0; k < 3; k++ {
				j := 6 + 3*k
				components[k] = Component{ID: int(a[j]), H: int(a[j+1] >> 4), V: int(a[j+1] & 15),
					Tq: int(a[j+2])}
			}
		case m == 221:
			name = "DRI"
			ri = readWord(a, 0)
		case m == 218:
			name = "SOS"
			for k := 0; k < 3; k++ {
				j := 1 + 2*k
				for v := range components {
					if components[v].ID == int(a[j]) {
						components[v].Td = int(a[j+1] >> 4)
						components[v].Ta = int(a[j+1] & 15)
					}
				}
			}
		}
		d.Segments = append(d.Segments,
			Segment{p, ls, name})
		p += ls + 2
		if m == 218 {
			break
		}
	}
	d.Segments = append(d.Segments, Segment{len(b) - 2, 0, "EOI"})
	d.Scan = len(b) - 2 - p
	d.G = geometry(w, h, ri, components)
	d.Blocks = blockOrder(d.G)
	d.Intervals = intervalOrder(d.G)
	perMCU := len(d.Blocks) / (d.G.MX * d.G.MY)
	r := BitReader{Bytes: b,
		Pos: p}
	for j := 0; j < len(d.Intervals); {
		iv := d.Intervals[j]
		first, end := iv.First*perMCU, (iv.First+iv.Count)*perMCU
		temp := make([][64]int,
			end-first)
		pred := [3]int{}
		kind := ""
		mcu := iv.First
		for bi := first; bi < end && kind == ""; bi++ {
			bl := d.Blocks[bi]
			mcu = bl.MCU
			co := components[bl.K]
			n,
				e := r.Symbol(d.Tables[co.Td])
			if e != "" {
				kind = e
				break
			}
			value, e := r.Read(n)
			if e != "" {
				kind = e
				break
			}
			pred[bl.K] += decodedExtra(value,
				n)
			z := &temp[bi-first]
			z[0] = pred[bl.K]
			for i := 1; i < 64; {
				a, e := r.Symbol(d.Tables[4+co.Ta])
				if e != "" {
					kind = e
					break
				}
				if a == 0 {
					break
				}
				i += a / 16
				n = a % 16
				if i > 63 {
					kind = "index"
					break
				}
				if n > 0 {
					v,
						e := r.Read(n)
					if e != "" {
						kind = e
						break
					}
					z[i] = decodedExtra(v, n)
				}
				i++
			}
		}
		r.Left = 0
		if kind == "" {
			expected := 217
			if j < len(d.Intervals)-1 {
				expected = 208 + j%8
			}
			if r.Pos+1 < len(b) && b[r.Pos] == 255 && int(b[r.Pos+1]) == expected {
				for bi := first; bi < end; bi++ {
					d.Blocks[bi].Z = temp[bi-first]
				}
				d.Intervals[j].State = "ok"
				r.Pos += 2
				j++
				continue
			}
			kind = "sync"
			mcu = iv.First + iv.Count - 1
		}
		offset := r.Pos
		q := resync(b,
			r.Pos)
		d.Intervals[j].State = fmt.Sprintf("damaged %s mcu %d offset %d resync %d", kind, mcu,
			offset, q)
		marker := int(b[q+1])
		r.Pos = q + 2
		if marker == 217 {
			break
		}
		j = j + 1 + (marker-208-j%8+8)%8
	}
	d.Planes = makePlanes(d.G, d.Blocks, d.Quant, c)
	d.Full, d.Image = upsample(d.Planes, d.G)
	return d
}
func sse(a, b []int) int {
	s := 0
	for i, v := range a {
		x := v - b[i]
		s += x * x
	}
	return s
}
func psnr(error, n int) string {
	if error == 0 {
		return "inf"
	}
	return fmt.Sprintf("%.2f", 10*math.Log10(65025*float64(n)/float64(error)))
}

type Metrics struct {
	PSNR [4]string
	Max  int
}

func evaluate(original Image, planes [3]Plane, d Decoding) Metrics {
	var m Metrics
	for k := 0; k < 3; k++ {
		m.PSNR[k] = psnr(sse(planes[k].A,
			d.Full[k].A), original.W*original.H)
	}
	m.PSNR[3] = psnr(sse(original.RGB, d.Image.RGB), len(original.RGB))
	for i, v := range original.RGB {
		m.Max = max(m.Max, abs(v-d.Image.RGB[i]))
	}
	return m
}
func gcd(a, b int) int {
	for b != 0 {
		a, b = b, a%b
	}
	return a
}
func fraction(a, b int) string { g := gcd(a, b); return fmt.Sprintf("%d/%d", a/g, b/g) }
func changed(a, b Image) int {
	n := 0
	for i := 0; i < a.W*a.H; i++ {
		if a.RGB[3*i] != b.RGB[3*i] || a.RGB[3*i+1] != b.RGB[3*i+1] || a.RGB[3*i+2] != b.RGB[3*i+2] {
			n++
		}
	}
	return n
}
func main() {
	im := readImage("input/image.ppm")
	params, t := readParameters(), readTables()
	must(os.MkdirAll("output",
		0755))
	orig := colors(im)
	var csv strings.Builder
	csv.WriteString("quality,bytes_standard,bytes_optimized,bpp,psnr_y,psnr_cb,psnr_cr,psnr_rgb,max_error\n")
	var ref Encoding
	var decoded Decoding
	for i, q := range params.Qualities {
		standard := encode(im, q, params.Sampling, "standard", params.Restart, t)
		opt := encode(im,
			q, params.Sampling, "optimized", params.Restart, t)
		e := standard
		if params.Mode == "optimized" {
			e = opt
		}
		d := decode(e.Bytes,
			t.C)
		m := evaluate(im, orig, d)
		fmt.Fprintf(&csv, "%d,%d,%d,%s,%s,%s,%s,%s,%d\n", q, len(standard.Bytes),
			len(opt.Bytes), fraction(8*len(e.Bytes), im.W*im.H), m.PSNR[0], m.PSNR[1], m.PSNR[2], m.PSNR[3], m.Max)
		if i == 0 {
			ref,
				decoded = e, d
		}
	}
	writeText("output/rate_distortion.csv", csv.String())
	writeImage("output/decoded.ppm",
		decoded.Image)
	writeHex("output/bitstream.hex", ref.Bytes)
	tw, th := (im.W+7)/8, (im.H+7)/8
	thumb := Image{tw, th, make([]int, 3*tw*th)}
	dc := map[[3]int]int{}
	for _, b := range ref.Blocks {
		dc[[3]int{b.K, b.BX, b.BY}] = b.Z[0]
	}
	for y := 0; y < th; y++ {
		for x := 0; x < tw; x++ {
			var a [3]int
			for k, c := range ref.G.Components {
				bx, by := x*c.H/ref.G.Hmax, y*c.V/ref.G.Vmax
				a[k] = clamp(floor(dc[[3]int{k,
					bx, by}]*ref.Quant[c.Tq][0]+4, 8) + 128)
			}
			v := rgb(a[0], a[1], a[2])
			copy(thumb.RGB[3*(y*tw+x):],
				v[:])
		}
	}
	writeImage("output/thumbnail.ppm", thumb)
	names := []string{"dc_luma", "ac_luma", "dc_chroma", "ac_chroma"}
	var ht strings.Builder
	for k, table := range ref.Tables {
		coded,
			bits := 0, 0
		for v, n := range ref.Counts[k] {
			coded += n
			bits += n * table.Length[v]
		}
		fmt.Fprintf(&ht,
			"table %s class %d id %d symbols %d coded %d bits %d\ncounts %s\n", names[k], k%2, k/2, len(table.Values),
			coded, bits, joined(table.Bits[1:]))
		for _, v := range table.Values {
			fmt.Fprintf(&ht, "symbol %02x length %d code %0*b count %d\n",
				v, table.Length[v], table.Length[v], table.Code[v], ref.Counts[k][v])
		}
	}
	writeText("output/huffman_tables.txt",
		ht.String())
	var bs strings.Builder
	fmt.Fprintf(&bs, "blocks %d\n", len(ref.Blocks))
	var nonzero [64]int
	var componentBits,
		componentNZ, componentSSE [3]int
	zeroAC := 0
	componentNames := []string{"Y", "Cb", "Cr"}
	for i, b := range ref.Blocks {
		n,
			last := 0, 0
		for k, v := range b.Z {
			if v != 0 {
				nonzero[k]++
				componentNZ[b.K]++
				if k > 0 {
					n++
					last = k
				}
			}
		}
		if n == 0 {
			zeroAC++
		}
		componentBits[b.K] += b.Bits
		a := blockPixels(ref.Source[b.K],
			b)
		r := blockPixels(decoded.Planes[b.K], b)
		err := sse(a[:], r[:])
		componentSSE[b.K] += err
		fmt.Fprintf(&bs,
			"block %d %s %d %d dc %d diff %d nonzero %d last %d bits %d sse %d\n", i, componentNames[b.K],
			b.BX, b.BY, b.Z[0], b.Diff, n, last, b.Bits, err)
	}
	writeText("output/blocks.txt", bs.String())
	stream := decode(readHex("input/stream.hex"), t.C)
	writeImage("output/stream_decoded.ppm", stream.Image)
	repairGeometry := stream.G
	for k := range repairGeometry.Components {
		c := &repairGeometry.Components[k]
		c.ID = k + 1
		c.Tq,
			c.Td, c.Ta = 1, 1, 1
		if k == 0 {
			c.Tq, c.Td, c.Ta = 0, 0, 0
		}
	}
	repairQuant := [2][64]int{stream.Quant[stream.G.Components[0].Tq],
		stream.Quant[stream.G.Components[1].Tq]}
	repaired := encodeCoefficients(repairGeometry, repairQuant,
		stream.Blocks, "optimized", t.Standard)
	writeHex("output/repaired.hex", repaired.Bytes)
	check := decode(repaired.Bytes,
		t.C)
	identical := "yes"
	for i, v := range stream.Image.RGB {
		if v != check.Image.RGB[i] {
			identical = "no"
		}
	}
	var report strings.Builder
	g := ref.G
	fmt.Fprintf(&report, "image %d %d\nsampling %s mcu %d %d grid %d %d\npadded %d %d\nblocks %d %d %d\nrestart_interval %d markers %d\nhuffman %s\nquality %d\n",
		im.W, im.H, params.Sampling, 8*g.Hmax, 8*g.Vmax, g.MX, g.MY, 8*g.Hmax*g.MX, 8*g.Vmax*g.MY, g.Components[0].H*g.Components[0].V*g.MX*g.MY,
		g.MX*g.MY, g.MX*g.MY, params.Restart, len(ref.Intervals)-1, params.Mode, params.Qualities[0])
	for k := 0; k < 2; k++ {
		fmt.Fprintf(&report,
			"quant %d %s\n", k, joined(ordered(ref.Quant[k])))
	}
	var counts [4]int
	for k := range counts {
		for _, v := range ref.Counts[k] {
			counts[k] += v
		}
	}
	fmt.Fprintf(&report, "symbols %s\neob %d zrl %d\nzero_ac_blocks %d\nnonzero %s\n",
		joined(counts[:]), ref.Counts[1][0]+ref.Counts[3][0], ref.Counts[1][240]+ref.Counts[3][240],
		zeroAC, joined(nonzero[:]))
	for k := 0; k < 3; k++ {
		fmt.Fprintf(&report, "component %s bits %d nonzero %d sse %d\n",
			componentNames[k], componentBits[k], componentNZ[k], componentSSE[k])
	}
	fmt.Fprintf(&report, "padding_bits %d\nstuffed_bytes %d\nheader_bytes %d\nscan_bytes %d\ntotal_bytes %d\n",
		ref.Padding, ref.Stuffed, ref.Header, ref.Scan, len(ref.Bytes))
	for j, iv := range ref.Intervals {
		fmt.Fprintf(&report,
			"interval %d %d %d %d %d\n", j, iv.First, iv.Count, iv.Position, iv.Length)
	}
	var histogram [8]int
	for i, v := range im.RGB {
		e := abs(v - decoded.Image.RGB[i])
		bin := 0
		switch {
		case e == 0:
			bin = 0
		case e == 1:
			bin = 1
		case e <= 3:
			bin = 2
		case e <= 7:
			bin = 3
		case e <= 15:
			bin = 4
		case e <= 31:
			bin = 5
		case e <= 63:
			bin = 6
		default:
			bin = 7
		}
		histogram[bin]++
	}
	fmt.Fprintf(&report,
		"error_histogram %s\n", joined(histogram[:]))
	for _, keep := range params.Truncate {
		b := append([]Block(nil), decoded.Blocks...)
		for i := range b {
			if b[i].K == 0 {
				for k := keep; k < 64; k++ {
					b[i].Z[k] = 0
				}
			}
		}
		p := makePlanes(decoded.G,
			b, decoded.Quant, t.C)
		a, _ := upsample(p, decoded.G)
		fmt.Fprintf(&report, "truncate %d %s\n", keep,
			psnr(sse(orig[0].A, a[0].A), im.W*im.H))
	}
	for _, s := range []string{"444", "422", "420"} {
		e := encode(im,
			params.Qualities[0], s, params.Mode, params.Restart, t)
		m := evaluate(im, orig, decode(e.Bytes, t.C))
		fmt.Fprintf(&report,
			"sampling_compare %s %d %s %s %s\n", s, len(e.Bytes), m.PSNR[1], m.PSNR[2], m.PSNR[3])
	}
	previous := im
	for generation := 1; generation <= params.Generations; generation++ {
		e := encode(previous,
			params.Qualities[0], params.Sampling, params.Mode, params.Restart, t)
		d := decode(e.Bytes, t.C)
		fmt.Fprintf(&report,
			"generation %d %d %s %d\n", generation, len(e.Bytes), psnr(sse(im.RGB, d.Image.RGB), len(im.RGB)),
			changed(previous, d.Image))
		previous = d.Image
	}
	lo, hi := 1, 100
	for lo < hi {
		mid := (lo + hi + 1) / 2
		e := encode(im,
			mid, params.Sampling, params.Mode, params.Restart, t)
		fmt.Fprintf(&report, "rate_control_step %d %d\n",
			mid, len(e.Bytes))
		if len(e.Bytes) <= params.Target {
			lo = mid
		} else {
			hi = mid - 1
		}
	}
	chosen := encode(im,
		lo, params.Sampling, params.Mode, params.Restart, t)
	fits := "no"
	if len(chosen.Bytes) <= params.Target {
		fits = "yes"
	}
	fmt.Fprintf(&report,
		"rate_control %d %d %s %s\n", lo, len(chosen.Bytes), fits, psnr(sse(im.RGB, decode(chosen.Bytes,
			t.C).Image.RGB), len(im.RGB)))
	for _, s := range stream.Segments {
		fmt.Fprintf(&report, "stream_segment %d %s %d\n", s.Position, s.Name,
			s.Length)
	}
	fmt.Fprintf(&report, "stream_image %d %d\n", stream.G.W, stream.G.H)
	for _, c := range stream.G.Components {
		fmt.Fprintf(&report,
			"stream_component %d %d %d %d %d %d\n", c.ID, c.H, c.V, c.Tq, c.Td, c.Ta)
	}
	keys := make([]int, 0, len(stream.Quant))
	for k := range stream.Quant {
		keys = append(keys,
			k)
	}
	sort.Ints(keys)
	for _, k := range keys {
		fmt.Fprintf(&report, "stream_quant %d %s\n", k, joined(ordered(stream.Quant[k])))
	}
	keys = nil
	for k := range stream.Tables {
		keys = append(keys,
			k)
	}
	sort.Ints(keys)
	for _, k := range keys {
		table := stream.Tables[k]
		longest := 0
		for l := 1; l <= 16; l++ {
			if table.Bits[l] > 0 {
				longest = l
			}
		}
		fmt.Fprintf(&report,
			"stream_huffman %d %d symbols %d longest %d\n", k/4, k%4, len(table.Values), longest)
	}
	ok, damaged,
		lost := 0, 0, 0
	for _, iv := range stream.Intervals {
		if iv.State == "ok" {
			ok++
		} else if iv.State == "lost" {
			lost++
		} else {
			damaged++
		}
	}
	fmt.Fprintf(&report,
		"stream_restart %d intervals %d ok %d damaged %d lost %d\n", stream.G.Restart, len(stream.Intervals),
		ok, damaged, lost)
	for j, iv := range stream.Intervals {
		fmt.Fprintf(&report, "stream_interval %d %d %d %s\n",
			j, iv.First, iv.Count, iv.State)
	}
	fmt.Fprintf(&report, "stream_scan_bytes %d\nrepair %d %d %d identical %s\n",
		stream.Scan, len(repaired.Bytes), repaired.Header, repaired.Scan, identical)
	writeText("output/report.txt",
		report.String())
}
