package main

import (
	"fmt"
	"math/bits"
	"os"
	"strconv"
	"strings"
)

var levels = []string{"L", "M", "Q", "H"}

type BlockTable struct{ e, b1, k1, b2, k2 int }

func (t BlockTable) data() int { return t.b1*t.k1 + t.b2*t.k2 }
func (t BlockTable) lengths() []int {
	a := make([]int, t.b1+t.b2)
	for i := range a {
		a[i] = t.k1
		if i >= t.b1 {
			a[i] = t.k2
		}
	}
	return a
}
func (t BlockTable) total() int { return t.data() + t.e*(t.b1+t.b2) }

type Segment struct{ mode, text string }
type Group struct {
	value, width int
	text         string
}
type Request struct{ id, level, mode, version, mask, text string }
type Damage struct {
	kind string
	args []string
}
type Result struct {
	lines     []string
	ok        bool
	text      string
	blocks    [3]int
	corrected int
}
type Prepared struct {
	request               Request
	mode, level           string
	version, mask, length int
	segments              []Segment
	table                 BlockTable
	data,
	interleaved []int
	blocks    [][]int
	placement []Point
	matrix    *Matrix
	symbol    [][]int
	penalties []Penalty
	terminator,
	zeroFill, pads int
}
type QR struct {
	tables       map[int]map[string]BlockTable
	alignment    map[int][]int
	field        *Field
	quiet, scale int
	requests     []Request
	damage       map[string][]Damage
	codes,
	codewords, bitstream, selfcheck, scans, capacity []string
	errorKinds, modeCounts, levelCounts, checkCounts map[string]int
	versions                                         [11]int
	masks                                            [8]int
	valid,
	boosted, segments, dataCount, ecCount, modules, dark, checks, corrected, scanCount, scanOK int
	blockCounts [3]int
}

func number(s string) int { v, _ := strconv.Atoi(s); return v }
func readLines(path string) []string {
	b, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	if len(b) == 0 {
		return nil
	}
	return strings.Split(strings.TrimSuffix(string(b),
		"\n"), "\n")
}
func line(out *[]string, format string, a ...any) { *out = append(*out, fmt.Sprintf(format, a...)) }
func countWidth(mode string, v int) int {
	if v == 10 {
		switch mode {
		case "NUMERIC":
			return 12
		case "ALPHANUMERIC":
			return 11
		default:
			return 16
		}
	}
	switch mode {
	case "NUMERIC":
		return 10
	case "ALPHANUMERIC":
		return 9
	default:
		return 8
	}
}
func dataWidth(mode string, n int) int {
	switch mode {
	case "NUMERIC":
		return 10*(n/3) + []int{0, 4, 7}[n%3]
	case "ALPHANUMERIC":
		return 11*(n/2) + 6*(n%2)
	default:
		return 8 * n
	}
}
func indicator(mode string) int {
	switch mode {
	case "NUMERIC":
		return 1
	case "ALPHANUMERIC":
		return 2
	default:
		return 4
	}
}
func encodable(mode string, c byte) bool {
	switch mode {
	case "NUMERIC":
		return c >= '0' && c <= '9'
	case "ALPHANUMERIC":
		return strings.IndexByte(alphanumeric,
			c) >= 0
	default:
		return true
	}
}
func canEncode(mode, text string) bool {
	for _, c := range []byte(text) {
		if !encodable(mode, c) {
			return false
		}
	}
	return true
}
func splitSegments(mode, text string, v int) ([]Segment, int) {
	if mode != "MIXED" {
		return []Segment{{mode,
			text}}, 4 + countWidth(mode, v) + dataWidth(mode, len(text))
	}
	n := len(text)
	cost := make([]int, n+1)
	starts := make([]int,
		n+1)
	chosen := make([]int, n+1)
	bad := make([][]int, 3)
	for mu, mode := range modes {
		bad[mu] = make([]int,
			n+1)
		for i, c := range []byte(text) {
			bad[mu][i+1] = bad[mu][i]
			if !encodable(mode, c) {
				bad[mu][i+1]++
			}
		}
	}
	for i := 1; i <= n; i++ {
		cost[i] = 1 << 30
		for j := 0; j < i; j++ {
			for mu, mode := range modes {
				if bad[mu][i] != bad[mu][j] {
					continue
				}
				value := cost[j] + 4 + countWidth(mode, v) + dataWidth(mode,
					i-j)
				if value < cost[i] {
					cost[i] = value
					starts[i] = j
					chosen[i] = mu
				}
			}
		}
	}
	var reversed []Segment
	for i := n; i > 0; {
		j := starts[i]
		reversed = append(reversed,
			Segment{modes[chosen[i]], text[j:i]})
		i = j
	}
	out := make([]Segment, len(reversed))
	for i := range out {
		out[i] = reversed[len(reversed)-1-i]
	}
	return out,
		cost[n]
}
func groups(segment Segment) []Group {
	mode, text := segment.mode, segment.text
	var out []Group
	size := 1
	if mode == "NUMERIC" {
		size = 3
	} else if mode == "ALPHANUMERIC" {
		size = 2
	}
	for start := 0; start < len(text); start += size {
		part := text[start:min(start+size,
			len(text))]
		value, width := 0, dataWidth(mode, len(part))
		switch mode {
		case "NUMERIC":
			value = number(part)
		case "ALPHANUMERIC":
			value = strings.IndexByte(alphanumeric,
				part[0])
			if len(part) == 2 {
				value = 45*value + strings.IndexByte(alphanumeric, part[1])
			}
		default:
			value = int(part[0])
		}
		out = append(out,
			Group{value, width, part})
	}
	return out
}
func padding(prefix []int, capacity int) ([]int, int, int, int) {
	out := append([]int(nil), prefix...)
	terminator := min(4,
		capacity-len(out))
	out = append(out, make([]int, terminator)...)
	zeroFill := (8 - len(out)%8) % 8
	out = append(out,
		make([]int, zeroFill)...)
	pads := 0
	b := Bits{values: out}
	for len(b.values) < capacity {
		value := 0xec
		if pads%2 == 1 {
			value = 0x11
		}
		b.append(value,
			8)
		pads++
	}
	return b.values, terminator, zeroFill, pads
}
func placementOrder(lengths []int, e int) []Point {
	var out []Point
	maximum := 0
	for _, k := range lengths {
		maximum = max(maximum,
			k)
	}
	for i := 0; i < maximum; i++ {
		for b, k := range lengths {
			if i < k {
				out = append(out, Point{b, i})
			}
		}
	}
	for i := 0; i < e; i++ {
		for b, k := range lengths {
			out = append(out, Point{b, k + i})
		}
	}
	return out
}
func (q *QR) prepare(r Request) (*Prepared, string) {
	if r.level != "L" && r.level != "M" && r.level != "Q" && r.level != "H" && r.level != "L+" && r.level != "M+" && r.level != "Q+" && r.level != "H+" {
		return nil,
			"level " + r.level
	}
	if r.mode != "NUMERIC" && r.mode != "ALPHANUMERIC" && r.mode != "BYTE" && r.mode != "AUTO" && r.mode != "MIXED" {
		return nil,
			"mode " + r.mode
	}
	if r.version != "AUTO" && (number(r.version) < 1 || number(r.version) > 10 || strconv.Itoa(number(r.version)) != r.version) {
		return nil,
			"version " + r.version
	}
	if r.mask != "AUTO" && (len(r.mask) != 1 || r.mask[0] < '0' || r.mask[0] > '7') {
		return nil,
			"mask " + r.mask
	}
	if len(r.text) == 0 {
		return nil, "text"
	}
	if r.mode == "NUMERIC" || r.mode == "ALPHANUMERIC" {
		for i, c := range []byte(r.text) {
			if !encodable(r.mode, c) {
				return nil, fmt.Sprintf("charset position %d",
					i)
			}
		}
	}
	mode := r.mode
	if mode == "AUTO" {
		for _, candidate := range modes {
			if canEncode(candidate, r.text) {
				mode = candidate
				break
			}
		}
	}
	base := r.level[:1]
	segments1,
		bits1 := splitSegments(mode, r.text, 1)
	segments10, bits10 := splitSegments(mode, r.text, 10)
	segmentsAt := func(v int) ([]Segment,
		int) {
		if v == 10 {
			return segments10, bits10
		}
		return segments1, bits1
	}
	version := number(r.version)
	if r.version == "AUTO" {
		for v := 1; v <= 10; v++ {
			_,
				length := segmentsAt(v)
			if length <= 8*q.tables[v][base].data() {
				version = v
				break
			}
		}
		if version == 0 {
			return nil,
				fmt.Sprintf("capacity bits %d capacity %d", bits10, 8*q.tables[10][base].data())
		}
	}
	segments, length := segmentsAt(version)
	if length > 8*q.tables[version][base].data() {
		return nil,
			fmt.Sprintf("capacity bits %d capacity %d", length, 8*q.tables[version][base].data())
	}
	level := base
	if len(r.level) == 2 {
		for _, candidate := range levels {
			if strings.Index("LMQH", candidate) >= strings.Index("LMQH", base) && length <= 8*q.tables[version][candidate].data() {
				level = candidate
			}
		}
	}
	p := &Prepared{request: r,
		mode: mode, level: level, version: version, length: length, segments: segments, table: q.tables[version][level],
		matrix: makeMatrix(version, q.alignment[version])}
	b := Bits{}
	for _, seg := range segments {
		b.append(indicator(seg.mode),
			4)
		b.append(len(seg.text), countWidth(seg.mode, version))
		for _, group := range groups(seg) {
			b.append(group.value,
				group.width)
		}
	}
	padded, t, z, pads := padding(b.values, 8*p.table.data())
	p.terminator, p.zeroFill, p.pads = t,
		z, pads
	p.data = wordsFromBits(padded)
	at := 0
	lengths := p.table.lengths()
	for _, k := range lengths {
		data := append([]int(nil),
			p.data[at:at+k]...)
		p.blocks = append(p.blocks, append(data, q.field.encode(data, p.table.e)...))
		at += k
	}
	p.placement = placementOrder(lengths,
		p.table.e)
	for _, position := range p.placement {
		p.interleaved = append(p.interleaved, p.blocks[position.x][position.y])
	}
	stream := bitsFromWords(p.interleaved)
	for j, position := range p.matrix.order {
		if j < len(stream) {
			p.matrix.values[position.y][position.x] = stream[j]
		}
	}
	f1,
		f2 := formatPositions(17 + 4*version)
	var symbols [][][]int
	for mask := 0; mask < 8; mask++ {
		symbol := applyMask(p.matrix.values,
			p.matrix.areas, mask)
		f := formatInformation(level, mask)
		writeInformation(symbol, f1, f)
		writeInformation(symbol,
			f2, f)
		symbols = append(symbols, symbol)
		p.penalties = append(p.penalties, penalty(symbol))
	}
	mask := number(r.mask)
	if r.mask == "AUTO" {
		for m := 1; m < 8; m++ {
			if p.penalties[m].total() < p.penalties[mask].total() {
				mask = m
			}
		}
	}
	p.mask = mask
	p.symbol = symbols[mask]
	return p,
		""
}
func (q *QR) attempt(a [][]int) Result {
	out := Result{}
	n := len(a)
	v := (n - 17) / 4
	f1, f2 := formatPositions(n)
	f,
		g := readInformation(a, f1), readInformation(a, f2)
	d1, d2 := 16, 16
	level1, level2 := "", ""
	mask1, mask2 := 0,
		0
	for _, level := range levels {
		for mask := 0; mask < 8; mask++ {
			information := formatInformation(level, mask)
			if d := bits.OnesCount(uint(f ^ information)); d < d1 {
				d1 = d
				level1 = level
				mask1 = mask
			}
			if d := bits.OnesCount(uint(g ^ information)); d < d2 {
				d2 = d
				level2 = level
				mask2 = mask
			}
		}
	}
	distance,
		level, mask := d1, level1, mask1
	if d2 < d1 {
		distance, level, mask = d2, level2, mask2
	}
	text := fmt.Sprintf("format %s %s distance %d %d",
		binary(f, 15), binary(g, 15), d1, d2)
	if distance > 3 {
		out.lines = append(out.lines, text+" unreadable")
		return out
	}
	line(&out.lines,
		"%s level %s mask %d", text, level, mask)
	if v >= 7 {
		p1, p2 := versionPositions(n)
		g1, g2 := readInformation(a,
			p1), readInformation(a, p2)
		e1, e2 := 19, 19
		v1, v2 := 0, 0
		for version := 7; version <= 40; version++ {
			information := versionInformation(version)
			if d := bits.OnesCount(uint(g1 ^ information)); d < e1 {
				e1 = d
				v1 = version
			}
			if d := bits.OnesCount(uint(g2 ^ information)); d < e2 {
				e2 = d
				v2 = version
			}
		}
		distance,
			version := e1, v1
		if e2 < e1 {
			distance, version = e2, v2
		}
		text := fmt.Sprintf("version %s %s distance %d %d",
			binary(g1, 18), binary(g2, 18), e1, e2)
		if distance > 3 {
			out.lines = append(out.lines, text+" unreadable")
			return out
		}
		line(&out.lines,
			"%s decoded %d", text, version)
		if version != v {
			return out
		}
	}
	table := q.tables[v][level]
	matrix := makeMatrix(v,
		q.alignment[v])
	unmasked := applyMask(a, matrix.areas, mask)
	stream := make([]int, 8*table.total())
	for i := range stream {
		p := matrix.order[i]
		stream[i] = unmasked[p.y][p.x]
	}
	words := wordsFromBits(stream)
	lengths := table.lengths()
	blocks := make([][]int,
		len(lengths))
	for b, k := range lengths {
		blocks[b] = make([]int, k+table.e)
	}
	for j, p := range placementOrder(lengths,
		table.e) {
		blocks[p.x][p.y] = words[j]
	}
	failed := false
	for b, block := range blocks {
		correction := q.field.correct(block,
			table.e)
		text := fmt.Sprintf("block %d syndromes %s", b, hexadecimal(correction.syndromes))
		if !correction.ok {
			out.lines = append(out.lines,
				text+" failed")
			out.blocks[2]++
			failed = true
		} else if len(correction.positions) == 0 {
			out.lines = append(out.lines,
				text+" ok")
			out.blocks[0]++
			blocks[b] = correction.words
		} else {
			var positions []string
			for _, p := range correction.positions {
				positions = append(positions,
					strconv.Itoa(p))
			}
			out.lines = append(out.lines, text+" corrected "+strings.Join(positions, " "))
			out.blocks[1]++
			out.corrected += len(correction.positions)
			blocks[b] = correction.words
		}
	}
	if failed {
		return out
	}
	var data []int
	for b, k := range lengths {
		data = append(data, blocks[b][:k]...)
	}
	b := Bits{values: bitsFromWords(data)}
	end := 0
	var decoded strings.Builder
	for len(b.values)-b.position >= 4 {
		modeBits := b.read(4)
		if modeBits == 0 {
			break
		}
		mode := ""
		switch modeBits {
		case 1:
			mode = "NUMERIC"
		case 2:
			mode = "ALPHANUMERIC"
		case 4:
			mode = "BYTE"
		default:
			line(&out.lines,
				"parse failed indicator %s", binary(modeBits, 4))
			return out
		}
		cw := countWidth(mode, v)
		if len(b.values)-b.position < cw {
			line(&out.lines,
				"parse failed length %s", mode)
			return out
		}
		k := b.read(cw)
		if len(b.values)-b.position < dataWidth(mode,
			k) {
			line(&out.lines, "parse failed length %s", mode)
			return out
		}
		size := 1
		if mode == "NUMERIC" {
			size = 3
		} else if mode == "ALPHANUMERIC" {
			size = 2
		}
		for j := 0; j < k; j += size {
			length := min(size,
				k-j)
			value := b.read(dataWidth(mode, length))
			valid := true
			switch mode {
			case "NUMERIC":
				limit := []int{1,
					10, 100, 1000}[length]
				if value >= limit {
					valid = false
				} else {
					fmt.Fprintf(&decoded, "%0*d", length, value)
				}
			case "ALPHANUMERIC":
				if length == 2 {
					if value >= 2025 {
						valid = false
					} else {
						decoded.WriteByte(alphanumeric[value/45])
						decoded.WriteByte(alphanumeric[value%45])
					}
				} else if value >= 45 {
					valid = false
				} else {
					decoded.WriteByte(alphanumeric[value])
				}
			case "BYTE":
				if value < 32 || value > 126 {
					valid = false
				} else {
					decoded.WriteByte(byte(value))
				}
			}
			if !valid {
				line(&out.lines,
					"parse failed value %s", mode)
				return out
			}
		}
		line(&out.lines, "segment %s %d", mode, k)
		end = b.position
	}
	padded,
		_, _, _ := padding(b.values[:end], len(b.values))
	equal := true
	for i, v := range padded {
		if b.values[i] != v {
			equal = false
			break
		}
	}
	if equal {
		out.lines = append(out.lines,
			"padding ok")
	} else {
		out.lines = append(out.lines, "padding bad")
	}
	out.text = decoded.String()
	line(&out.lines,
		"text \"%s\"", out.text)
	out.ok = true
	return out
}
func (q *QR) decode(a [][]int) Result {
	n := len(a)
	corners := []Point{{n - 7, n - 7}, {n - 7, 0}, {0, 0}, {0, n - 7}}
	rotation,
		best := 0, 50
	for k, c := range corners {
		score := 0
		for y := 0; y < 7; y++ {
			for x := 0; x < 7; x++ {
				expected := 1
				if max(abs(x-3),
					abs(y-3)) == 2 {
					expected = 0
				}
				if a[c.y+y][c.x+x] == expected {
					score++
				}
			}
		}
		if score < best {
			best = score
			rotation = k
		}
	}
	for k := 0; k < rotation; k++ {
		a = rotate(a)
	}
	result := q.attempt(a)
	mirrored := "no"
	if !result.ok {
		second := q.attempt(transpose(a))
		if second.ok {
			result = second
			mirrored = "yes"
		}
	}
	result.lines = append([]string{fmt.Sprintf("orientation rotations %d mirrored %s",
		rotation, mirrored)}, result.lines...)
	return result
}
func imageRead(text string) ([][]int, string) {
	lines := strings.Split(strings.TrimSuffix(text, "\n"), "\n")
	size := strings.Fields(lines[1])
	w,
		h := number(size[0]), number(size[1])
	pixels := lines[2:]
	left, right, top := w, -1, h
	for y, row := range pixels {
		for x, c := range row {
			if c == '1' {
				left = min(left, x)
				right = max(right, x)
				top = min(top, y)
			}
		}
	}
	run := 0
	for x := left; x < w && pixels[top][x] == '1'; x++ {
		run++
	}
	scale := run / 7
	n := (right - left + 1) / scale
	a := intGrid(n)
	for y := 0; y < n; y++ {
		for x := 0; x < n; x++ {
			a[y][x] = int(pixels[top+scale*y][left+scale*x] - '0')
		}
	}
	well := true
	for y, row := range pixels {
		for x, c := range row {
			expected := 0
			if x >= left && x < left+scale*n && y >= top && y < top+scale*n {
				expected = a[(y-top)/scale][(x-left)/scale]
			}
			if int(c-'0') != expected {
				well = false
			}
		}
	}
	status := "ok"
	if !well {
		status = "bad"
	}
	return a,
		fmt.Sprintf("image %d %d quiet %d scale %d size %d %s", w, h, left/scale, scale, n, status)
}
func (q *QR) check(result Result, expected string) string {
	status := "failed"
	if result.ok {
		status = "mismatch"
		if result.text == expected {
			status = "ok"
		}
	}
	q.checks++
	q.checkCounts[status]++
	for i, n := range result.blocks {
		q.blockCounts[i] += n
	}
	q.corrected += result.corrected
	return status
}
func (q *QR) tolerance(p *Prepared, color int) int {
	n := len(p.symbol)
	for size := 1; size <= n; size++ {
		a := (n - size) / 2
		damaged := cloneGrid(p.symbol)
		for y := a; y < a+size; y++ {
			for x := a; x < a+size; x++ {
				damaged[y][x] = color
			}
		}
		result := q.decode(damaged)
		if !result.ok || result.text != p.request.text {
			return size - 1
		}
	}
	return n
}
func (q *QR) emit(p *Prepared) {
	r := p.request
	n := len(p.symbol)
	table := p.table
	dark := 0
	for _, row := range p.symbol {
		for _, v := range row {
			dark += v
		}
	}
	q.valid++
	q.modeCounts[p.mode]++
	q.levelCounts[p.level]++
	q.versions[p.version]++
	q.masks[p.mask]++
	q.segments += len(p.segments)
	q.dataCount += table.data()
	q.ecCount += table.e * (table.b1 + table.b2)
	q.modules += n * n
	q.dark += dark
	if p.level != r.level[:1] {
		q.boosted++
	}
	line(&q.codes,
		"symbol version %d level %s mask %d size %d", p.version, p.level, p.mask, n)
	var segments []string
	for _, seg := range p.segments {
		segments = append(segments, fmt.Sprintf("%s:%d", seg.mode, len(seg.text)))
	}
	line(&q.codes,
		"segments %d %s", len(segments), strings.Join(segments, " "))
	alternatives := make([]string, 3)
	for i, mode := range modes {
		alternatives[i] = "-"
		if canEncode(mode, r.text) {
			alternatives[i] = strconv.Itoa(4 + countWidth(mode,
				p.version) + dataWidth(mode, len(r.text)))
		}
	}
	_, mixed := splitSegments("MIXED", r.text, p.version)
	line(&q.codes,
		"bits data %d capacity %d alternatives NUMERIC %s ALPHANUMERIC %s BYTE %s MIXED %d", p.length,
		8*table.data(), alternatives[0], alternatives[1], alternatives[2], mixed)
	var fits []string
	segments1,
		length1 := splitSegments(p.mode, r.text, 1)
	_ = segments1
	_, length10 := splitSegments(p.mode, r.text,
		10)
	for _, level := range levels {
		fit := "-"
		for v := 1; v <= 10; v++ {
			length := length1
			if v == 10 {
				length = length10
			}
			if length <= 8*q.tables[v][level].data() {
				fit = strconv.Itoa(v)
				break
			}
		}
		fits = append(fits,
			fit)
	}
	line(&q.codes, "fits L %s M %s Q %s H %s", fits[0], fits[1], fits[2], fits[3])
	line(&q.codes,
		"modules function %d data %d remainder %d dark %d", n*n-len(p.matrix.order), len(p.matrix.order),
		len(p.matrix.order)-8*table.total(), dark)
	versionInfo := "none"
	if p.version >= 7 {
		versionInfo = binary(versionInformation(p.version),
			18)
	}
	line(&q.codes, "format %s version %s", binary(formatInformation(p.level, p.mask), 15), versionInfo)
	for mask, a := range p.penalties {
		line(&q.codes, "penalty %d n1 %d n2 %d n3 %d n4 %d total %d", mask, a.n1, a.n2,
			a.n3, a.n4, a.total())
	}
	q.codes = append(q.codes, symbolLines(p.symbol)...)
	line(&q.codewords, "request %s version %d level %s blocks %d data %d ec_per_block %d total %d",
		r.id, p.version, p.level, len(p.blocks), table.data(), table.e, table.total())
	for b, block := range p.blocks {
		k := len(block) - table.e
		line(&q.codewords,
			"block %d data %s", b, hexadecimal(block[:k]))
		line(&q.codewords, "block %d ec %s", b, hexadecimal(block[k:]))
	}
	line(&q.codewords,
		"interleaved %s", hexadecimal(p.interleaved))
	line(&q.bitstream, "request %s version %d bits %d capacity %d",
		r.id, p.version, p.length, 8*table.data())
	for _, seg := range p.segments {
		line(&q.bitstream, "segment %s indicator %s count %d %s",
			seg.mode, binary(indicator(seg.mode), 4), len(seg.text), binary(len(seg.text), countWidth(seg.mode,
				p.version)))
		for _, g := range groups(seg) {
			line(&q.bitstream, "group %d %s \"%s\"", g.value, binary(g.value,
				g.width), g.text)
		}
	}
	line(&q.bitstream, "terminator %d zero_fill %d pad_bytes %d", p.terminator, p.zeroFill,
		p.pads)
	image := pbm(p.symbol, q.quiet, q.scale)
	if err := os.WriteFile("output/qr_"+r.id+".pbm", []byte(image),
		0644); err != nil {
		panic(err)
	}
	array, imageLine := imageRead(image)
	line(&q.selfcheck, "request %s", r.id)
	q.selfcheck = append(q.selfcheck,
		imageLine, "check clean")
	result := q.decode(array)
	q.selfcheck = append(q.selfcheck, result.lines...)
	line(&q.selfcheck,
		"result %s", q.check(result, r.text))
	if operations := q.damage[r.id]; len(operations) > 0 {
		damaged := cloneGrid(p.symbol)
		for _, operation := range operations {
			a := operation.args
			switch operation.kind {
			case "flip":
				x, y := number(a[0]),
					number(a[1])
				damaged[y][x] ^= 1
			case "fill":
				x, y, w, h := number(a[0]), number(a[1]), number(a[2]), number(a[3])
				color := 0
				if a[4] == "dark" {
					color = 1
				}
				for row := y; row < y+h; row++ {
					for col := x; col < x+w; col++ {
						damaged[row][col] = color
					}
				}
			}
		}
		changed,
			functions, formats, versions, data, remainder := 0, 0, 0, 0, 0, 0
		index := map[Point]int{}
		for j, p := range p.matrix.order {
			index[p] = j
		}
		damagedWords := make([]map[int]bool,
			len(p.blocks))
		for b := range damagedWords {
			damagedWords[b] = map[int]bool{}
		}
		for y := 0; y < n; y++ {
			for x := 0; x < n; x++ {
				if damaged[y][x] == p.symbol[y][x] {
					continue
				}
				changed++
				switch p.matrix.areas[y][x] {
				case 1:
					functions++
				case 2:
					formats++
				case 3:
					versions++
				case 0:
					j := index[Point{x,
						y}]
					if j >= 8*table.total() {
						remainder++
					} else {
						data++
						position := p.placement[j/8]
						damagedWords[position.x][position.y] = true
					}
				}
			}
		}
		line(&q.selfcheck,
			"check damaged operations %d", len(operations))
		line(&q.selfcheck, "damage changed %d function %d format %d version %d data %d remainder %d",
			changed, functions, formats, versions, data, remainder)
		var errors []string
		for _, words := range damagedWords {
			errors = append(errors,
				strconv.Itoa(len(words)))
		}
		line(&q.selfcheck, "errors %s limit %d", strings.Join(errors, " "), table.e/2)
		for _, operation := range operations {
			if operation.kind == "rotate" {
				damaged = rotate(damaged)
			} else if operation.kind == "mirror" {
				damaged = transpose(damaged)
			}
		}
		result = q.decode(damaged)
		q.selfcheck = append(q.selfcheck,
			result.lines...)
		line(&q.selfcheck, "result %s", q.check(result, r.text))
	}
	light := q.tolerance(p,
		0)
	darkTolerance := q.tolerance(p, 1)
	line(&q.selfcheck, "tolerance light %d dark %d", light, darkTolerance)
}
func (q *QR) capacityTable() {
	for v := 1; v <= 10; v++ {
		m := makeMatrix(v, q.alignment[v])
		n := 17 + 4*v
		table := q.tables[v]["L"]
		var coordinates []string
		for _, c := range q.alignment[v] {
			coordinates = append(coordinates, strconv.Itoa(c))
		}
		alignment := strings.Join(coordinates,
			" ")
		if alignment == "" {
			alignment = "none"
		}
		line(&q.capacity, "version %d size %d data_modules %d codewords %d remainder %d alignment %s",
			v, n, len(m.order), table.total(), len(m.order)-8*table.total(), alignment)
		for _, level := range levels {
			table = q.tables[v][level]
			maximum := make([]int,
				3)
			for mu, mode := range modes {
				k := 0
				for 4+countWidth(mode, v)+dataWidth(mode, k+1) <= 8*table.data() {
					k++
				}
				maximum[mu] = k
			}
			line(&q.capacity,
				"level %s blocks %d data %d ec_per_block %d numeric %d alphanumeric %d byte %d", level, table.b1+table.b2,
				table.data(), table.e, maximum[0], maximum[1], maximum[2])
		}
	}
}
func (q *QR) summary() []string {
	var out []string
	line(&out, "requests %d encoded %d errors %d", len(q.requests),
		q.valid, len(q.requests)-q.valid)
	line(&out, "error_kinds level %d mode %d version %d mask %d text %d charset %d capacity %d",
		q.errorKinds["level"], q.errorKinds["mode"], q.errorKinds["version"], q.errorKinds["mask"], q.errorKinds["text"],
		q.errorKinds["charset"], q.errorKinds["capacity"])
	line(&out, "modes NUMERIC %d ALPHANUMERIC %d BYTE %d MIXED %d",
		q.modeCounts["NUMERIC"], q.modeCounts["ALPHANUMERIC"], q.modeCounts["BYTE"], q.modeCounts["MIXED"])
	line(&out,
		"levels L %d M %d Q %d H %d boosted %d", q.levelCounts["L"], q.levelCounts["M"], q.levelCounts["Q"],
		q.levelCounts["H"], q.boosted)
	var versions, masks []string
	for v := 1; v <= 10; v++ {
		versions = append(versions,
			strconv.Itoa(q.versions[v]))
	}
	for _, count := range q.masks {
		masks = append(masks, strconv.Itoa(count))
	}
	line(&out,
		"versions %s", strings.Join(versions, " "))
	line(&out, "masks %s", strings.Join(masks, " "))
	line(&out,
		"segments %d data_codewords %d ec_codewords %d", q.segments, q.dataCount, q.ecCount)
	line(&out, "modules %d dark %d",
		q.modules, q.dark)
	line(&out, "checks %d ok %d mismatch %d failed %d", q.checks, q.checkCounts["ok"],
		q.checkCounts["mismatch"], q.checkCounts["failed"])
	line(&out, "blocks ok %d corrected %d failed %d codewords %d",
		q.blockCounts[0], q.blockCounts[1], q.blockCounts[2], q.corrected)
	line(&out, "scans %d decoded %d failed %d",
		q.scanCount, q.scanOK, q.scanCount-q.scanOK)
	return out
}
func main() {
	q := &QR{tables: map[int]map[string]BlockTable{}, alignment: map[int][]int{}, field: newField(),
		damage: map[string][]Damage{}, errorKinds: map[string]int{}, modeCounts: map[string]int{}, levelCounts: map[string]int{},
		checkCounts: map[string]int{}}
	params := readLines("input/params.txt")
	q.quiet = number(strings.Fields(params[0])[1])
	q.scale = number(strings.Fields(params[1])[1])
	for _, line := range readLines("input/tables.txt") {
		a := strings.Fields(line)
		v := number(a[1])
		if a[0] == "block" {
			if q.tables[v] == nil {
				q.tables[v] = map[string]BlockTable{}
			}
			q.tables[v][a[2]] = BlockTable{number(a[3]),
				number(a[4]), number(a[5]), number(a[6]), number(a[7])}
		} else {
			for _, s := range a[2:] {
				q.alignment[v] = append(q.alignment[v],
					number(s))
			}
		}
	}
	for _, line := range readLines("input/requests.txt") {
		at := strings.IndexByte(line, ':')
		a := strings.Fields(line[:at])
		q.requests = append(q.requests,
			Request{a[0], a[1], a[2], a[3], a[4], line[at+1:]})
	}
	for _, line := range readLines("input/damage.txt") {
		a := strings.Fields(line)
		q.damage[a[0]] = append(q.damage[a[0]],
			Damage{a[1], a[2:]})
	}
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	for _, r := range q.requests {
		line(&q.codes,
			"request %s", r.id)
		p, errorText := q.prepare(r)
		if errorText != "" {
			line(&q.codes, "error %s", errorText)
			q.errorKinds[strings.Fields(errorText)[0]]++
			continue
		}
		q.emit(p)
	}
	lines := readLines("input/scans.txt")
	for at := 0; at < len(lines); {
		name := strings.Fields(lines[at])[1]
		at++
		n := len(lines[at])
		a := intGrid(n)
		for y := 0; y < n; y++ {
			for x, c := range lines[at+y] {
				if c == '#' {
					a[y][x] = 1
				}
			}
		}
		at += n
		q.scanCount++
		result := q.decode(a)
		line(&q.scans,
			"scan %s size %d", name, n)
		q.scans = append(q.scans, result.lines...)
		if result.ok {
			q.scanOK++
			q.scans = append(q.scans,
				"result decoded")
		} else {
			q.scans = append(q.scans, "result failed")
		}
	}
	q.capacityTable()
	reports := map[string][]string{"codes.txt": q.codes,
		"codewords.txt": q.codewords, "bitstream.txt": q.bitstream, "selfcheck.txt": q.selfcheck, "scans.txt": q.scans,
		"capacity.txt": q.capacity, "summary.txt": q.summary()}
	for name, lines := range reports {
		text := ""
		if len(lines) > 0 {
			text = strings.Join(lines,
				"\n") + "\n"
		}
		if err := os.WriteFile("output/"+name, []byte(text), 0644); err != nil {
			panic(err)
		}
	}
}
