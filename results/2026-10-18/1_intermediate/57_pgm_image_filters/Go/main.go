package main

import (
	"bufio"
	"fmt"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

var (
	integerWord = regexp.MustCompile(`^(?:0|-?[1-9][0-9]{0,6})$`)
	nameWord    = regexp.MustCompile(`^[a-z]{1,8}$`)
	digits      = regexp.MustCompile(`^[0-9]+$`)
	patterns    = map[string]string{
		"NEW": "iiii", "OUTPUT": "", "INVERT": "", "BRIGHTNESS": "i",
		"CONTRAST": "ii", "THRESHOLD": "i", "LEVELS": "ii", "POSTERIZE": "i",
		"MAXVAL": "i", "FLIPH": "", "FLIPV": "", "ROTATE": "i",
		"CROP": "iiii", "PAD": "ii", "SCALE": "ii", "SHIFT": "iii",
		"TILE": "ii", "BLUR": "", "GAUSS": "", "SHARPEN": "",
		"CONVOLVE": "iiiiiiiiii", "SOBEL": "", "MEDIAN": "", "ERODE": "",
		"DILATE": "", "OPEN": "", "CLOSE": "", "GRADIENT": "",
		"LINE": "iiiii", "RECT": "iiiii", "CIRCLE": "iiii", "FLOOD": "iii",
		"HISTOGRAM": "", "EQUALIZE": "", "LABEL": "i", "DISTANCE": "i",
		"STATS": "", "REGION": "iiii", "DITHER": "", "ASCIIART": "",
		"STORE": "n", "RECALL": "n", "DROP": "n", "BLEND": "nii",
		"DIFF": "n", "PASTE": "nii", "SLOTS": "", "INFO": "", "UNDO": "", "REDO": "",
	}
	kernels = map[string]struct {
		weights [9]int
		divisor int
	}{
		"BLUR": {[9]int{1, 1, 1, 1, 1, 1, 1, 1, 1}, 9},
		"GAUSS": {[9]int{1, 2, 1, 2, 4, 2, 1, 2, 1}, 16},
		"SHARPEN": {[9]int{0, -1, 0, -1, 5, -1, 0, -1, 0}, 1},
	}
	neighbors4 = [][2]int{{0, -1}, {-1, 0}, {1, 0}, {0, 1}}
	neighbors8 = [][2]int{
		{-1, -1}, {0, -1}, {1, -1}, {-1, 0}, {1, 0}, {-1, 1}, {0, 1}, {1, 1},
	}
)

const shades = "@#*+=~-:,."

func number(text string) int {
	n, _ := strconv.Atoi(text)
	return n
}

func sum(values []int) int {
	result := 0
	for _, value := range values {
		result += value
	}
	return result
}

func clamp(value, low, high int) int {
	if value < low {
		return low
	}
	if value > high {
		return high
	}
	return value
}

func floorDiv(n, d int) int {
	if n >= 0 {
		return n / d
	}
	return -((-n + d - 1) / d)
}

func withinLimit(values ...int) bool {
	for _, value := range values {
		if value < -1000 || value > 1000 {
			return false
		}
	}
	return true
}

func check(condition bool, reason string) error {
	if !condition {
		return fmt.Errorf("%s", reason)
	}
	return nil
}

type Image struct {
	Width, Height, Maxval int
	Pixels                []int
}

func newImage(width, height, maxval int, pixels []int) *Image {
	return &Image{width, height, maxval, pixels}
}

func (im *Image) get(x, y int) int {
	return im.Pixels[y*im.Width+x]
}

func (im *Image) row(y int) []int {
	return im.Pixels[y*im.Width : (y+1)*im.Width]
}

func (im *Image) contains(x, y int) bool {
	return x >= 0 && y >= 0 && x < im.Width && y < im.Height
}

func (im *Image) clamp(value int) int {
	return clamp(value, 0, im.Maxval)
}

func (im *Image) withPixels(pixels []int) *Image {
	return newImage(im.Width, im.Height, im.Maxval, pixels)
}

func (im *Image) neighborhood(x, y int) [9]int {
	var result [9]int
	for dy := -1; dy <= 1; dy++ {
		for dx := -1; dx <= 1; dx++ {
			nx := clamp(x+dx, 0, im.Width-1)
			ny := clamp(y+dy, 0, im.Height-1)
			result[(dy+1)*3+dx+1] = im.get(nx, ny)
		}
	}
	return result
}

func (im *Image) summary() string {
	checksum := 0
	for index, pixel := range im.Pixels {
		checksum += (index + 1) * pixel
	}
	return fmt.Sprintf("%dx%d maxval %d checksum %d", im.Width, im.Height, im.Maxval, checksum)
}

func readPGM(lines []string) (*Image, error) {
	words := []string{}
	for _, line := range lines {
		before, _, _ := strings.Cut(line, "#")
		words = append(words, strings.Fields(before)...)
	}
	if len(words) == 0 || words[0] != "P2" {
		return nil, fmt.Errorf("bad magic")
	}
	header := func(index, maximum int, reason string) (int, error) {
		if index >= len(words) {
			return 0, fmt.Errorf("truncated header")
		}
		if !digits.MatchString(words[index]) {
			return 0, fmt.Errorf("bad number")
		}
		value := number(words[index])
		if value < 1 || value > maximum {
			return 0, fmt.Errorf("%s", reason)
		}
		return value, nil
	}
	width, err := header(1, 64, "bad size")
	if err != nil {
		return nil, err
	}
	height, err := header(2, 64, "bad size")
	if err != nil {
		return nil, err
	}
	maxval, err := header(3, 255, "bad maxval")
	if err != nil {
		return nil, err
	}
	values := words[4:]
	needed := width * height
	pixels := make([]int, 0, needed)
	for index := 0; index < needed; index++ {
		if index >= len(values) {
			return nil, fmt.Errorf("too few pixels (%d of %d)", len(values), needed)
		}
		x, y := index%width, index/width
		word := values[index]
		if !digits.MatchString(word) {
			return nil, fmt.Errorf("bad pixel at %d,%d", x, y)
		}
		pixel := number(word)
		if pixel > maxval {
			return nil, fmt.Errorf("pixel out of range at %d,%d", x, y)
		}
		pixels = append(pixels, pixel)
	}
	if len(values) > needed {
		return nil, fmt.Errorf("too many pixels (%d of %d)", len(values), needed)
	}
	return newImage(width, height, maxval, pixels), nil
}

func transformed(im *Image, width, height int, pixelAt func(int, int) int) *Image {
	pixels := make([]int, 0, width*height)
	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			pixels = append(pixels, pixelAt(x, y))
		}
	}
	return newImage(width, height, im.Maxval, pixels)
}

func rotated(im *Image, angle int) *Image {
	w, h := im.Width, im.Height
	if angle == 180 {
		return transformed(im, w, h, func(x, y int) int {
			return im.get(w-1-x, h-1-y)
		})
	}
	if angle == 90 {
		return transformed(im, h, w, func(x, y int) int {
			return im.get(y, h-1-x)
		})
	}
	return transformed(im, h, w, func(x, y int) int {
		return im.get(w-1-y, x)
	})
}

func cropped(im *Image, x, y, w, h int) *Image {
	return transformed(im, w, h, func(i, j int) int {
		return im.get(x+i, y+j)
	})
}

func translated(im *Image, width, height, dx, dy, fill int) *Image {
	return transformed(im, width, height, func(x, y int) int {
		if im.contains(x-dx, y-dy) {
			return im.get(x-dx, y-dy)
		}
		return fill
	})
}

func scaled(im *Image, width, height, numerator, denominator int) *Image {
	return transformed(im, width, height, func(x, y int) int {
		sourceX := (2*x + 1) * denominator / (2 * numerator)
		sourceY := (2*y + 1) * denominator / (2 * numerator)
		return im.get(sourceX, sourceY)
	})
}

func convolution(im *Image, kernel [9]int, divisor int) *Image {
	return transformed(im, im.Width, im.Height, func(x, y int) int {
		near := im.neighborhood(x, y)
		total := 0
		for i, weight := range kernel {
			total += weight * near[i]
		}
		return im.clamp(floorDiv(total, divisor))
	})
}

func rankFiltered(im *Image, rank int) *Image {
	return transformed(im, im.Width, im.Height, func(x, y int) int {
		near := im.neighborhood(x, y)
		values := near[:]
		sort.Ints(values)
		return values[rank]
	})
}

func sobel(im *Image) *Image {
	return transformed(im, im.Width, im.Height, func(x, y int) int {
		q := im.neighborhood(x, y)
		gx := q[2] + 2*q[5] + q[8] - q[0] - 2*q[3] - q[6]
		gy := q[6] + 2*q[7] + q[8] - q[0] - 2*q[1] - q[2]
		return im.clamp(abs(gx) + abs(gy))
	})
}

func abs(n int) int {
	if n < 0 {
		return -n
	}
	return n
}

type Point struct {
	X, Y int
}

func linePoints(x0, y0, x1, y1 int) []Point {
	dx, dy := abs(x1-x0), -abs(y1-y0)
	sx, sy := -1, -1
	if x0 < x1 {
		sx = 1
	}
	if y0 < y1 {
		sy = 1
	}
	e := dx + dy
	points := []Point{}
	for {
		points = append(points, Point{x0, y0})
		if x0 == x1 && y0 == y1 {
			return points
		}
		twice := 2 * e
		if twice >= dy {
			e += dy
			x0 += sx
		}
		if twice <= dx {
			e += dx
			y0 += sy
		}
	}
}

func rectanglePoints(im *Image, x, y, width, height int, fill bool) []Point {
	right, bottom := x+width-1, y+height-1
	points := []Point{}
	for j := max(y, 0); j <= min(bottom, im.Height-1); j++ {
		for i := max(x, 0); i <= min(right, im.Width-1); i++ {
			if fill || i == x || i == right || j == y || j == bottom {
				points = append(points, Point{i, j})
			}
		}
	}
	return points
}

func circlePoints(cx, cy, radius int) []Point {
	a, b, e := radius, 0, 1-radius
	points := []Point{}
	for a >= b {
		points = append(points,
			Point{cx + a, cy + b}, Point{cx + b, cy + a},
			Point{cx - b, cy + a}, Point{cx - a, cy + b},
			Point{cx - a, cy - b}, Point{cx - b, cy - a},
			Point{cx + b, cy - a}, Point{cx + a, cy - b},
		)
		b++
		if e < 0 {
			e += 2*b + 1
		} else {
			a--
			e += 2*(b-a) + 1
		}
	}
	return points
}

func discPoints(im *Image, outline []Point) []Point {
	spans := make(map[int][2]int)
	for _, p := range outline {
		span, ok := spans[p.Y]
		if !ok {
			spans[p.Y] = [2]int{p.X, p.X}
		} else {
			spans[p.Y] = [2]int{min(span[0], p.X), max(span[1], p.X)}
		}
	}
	result := []Point{}
	for y, span := range spans {
		if y < 0 || y >= im.Height {
			continue
		}
		for x := max(span[0], 0); x <= min(span[1], im.Width-1); x++ {
			result = append(result, Point{x, y})
		}
	}
	return result
}

func floodPoints(im *Image, x, y int) []Point {
	target := im.get(x, y)
	seen := make([]bool, len(im.Pixels))
	seen[y*im.Width+x] = true
	stack, points := []Point{{x, y}}, []Point{}
	for len(stack) > 0 {
		p := stack[len(stack)-1]
		stack = stack[:len(stack)-1]
		points = append(points, p)
		for _, dir := range neighbors4 {
			nx, ny := p.X+dir[0], p.Y+dir[1]
			if !im.contains(nx, ny) || im.get(nx, ny) != target {
				continue
			}
			index := ny*im.Width + nx
			if !seen[index] {
				seen[index] = true
				stack = append(stack, Point{nx, ny})
			}
		}
	}
	return points
}

func equalized(im *Image) *Image {
	counts := make([]int, im.Maxval+1)
	minimum := im.Maxval
	for _, p := range im.Pixels {
		counts[p]++
		if p < minimum {
			minimum = p
		}
	}
	cdf, accumulated := make([]int, len(counts)), 0
	for i, n := range counts {
		accumulated += n
		cdf[i] = accumulated
	}
	n, cmin := len(im.Pixels), cdf[minimum]
	if n == cmin {
		return im.withPixels(append([]int(nil), im.Pixels...))
	}
	span := n - cmin
	pixels := make([]int, len(im.Pixels))
	for i, p := range im.Pixels {
		pixels[i] = (2*(cdf[p]-cmin)*im.Maxval + span) / (2 * span)
	}
	return im.withPixels(pixels)
}

func components(im *Image, threshold int) [][]Point {
	seen := make([]bool, len(im.Pixels))
	groups := [][]Point{}
	for index, pixel := range im.Pixels {
		if pixel < threshold || seen[index] {
			continue
		}
		seen[index] = true
		stack := []Point{{index % im.Width, index / im.Width}}
		members := []Point{}
		for len(stack) > 0 {
			p := stack[len(stack)-1]
			stack = stack[:len(stack)-1]
			members = append(members, p)
			for _, dir := range neighbors8 {
				nx, ny := p.X+dir[0], p.Y+dir[1]
				if !im.contains(nx, ny) {
					continue
				}
				i := ny*im.Width + nx
				if im.Pixels[i] >= threshold && !seen[i] {
					seen[i] = true
					stack = append(stack, Point{nx, ny})
				}
			}
		}
		groups = append(groups, members)
	}
	return groups
}

func componentText(im *Image, threshold int, members []Point) string {
	minX, minY := im.Width, im.Height
	maxX, maxY, totalX, totalY, perimeter := 0, 0, 0, 0, 0
	for _, p := range members {
		minX, minY = min(minX, p.X), min(minY, p.Y)
		maxX, maxY = max(maxX, p.X), max(maxY, p.Y)
		totalX += p.X
		totalY += p.Y
		for _, dir := range neighbors4 {
			nx, ny := p.X+dir[0], p.Y+dir[1]
			if !im.contains(nx, ny) || im.get(nx, ny) < threshold {
				perimeter++
				break
			}
		}
	}
	area := len(members)
	return fmt.Sprintf("area %d perimeter %d box %d %d %d %d center %d %d",
		area, perimeter, minX, minY, maxX, maxY, totalX/area, totalY/area)
}

func distanceMap(im *Image, threshold int) *Image {
	w, h := im.Width, im.Height
	far := w + h
	distances := make([]int, len(im.Pixels))
	hasBackground := false
	for i, p := range im.Pixels {
		if p < threshold {
			hasBackground = true
			distances[i] = 0
		} else {
			distances[i] = far
		}
	}
	if !hasBackground {
		for i := range distances {
			distances[i] = im.Maxval
		}
		return im.withPixels(distances)
	}
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			i := y*w + x
			if x > 0 {
				distances[i] = min(distances[i], distances[i-1]+1)
			}
			if y > 0 {
				distances[i] = min(distances[i], distances[i-w]+1)
			}
		}
	}
	for y := h - 1; y >= 0; y-- {
		for x := w - 1; x >= 0; x-- {
			i := y*w + x
			if x+1 < w {
				distances[i] = min(distances[i], distances[i+1]+1)
			}
			if y+1 < h {
				distances[i] = min(distances[i], distances[i+w]+1)
			}
		}
	}
	for i, distance := range distances {
		distances[i] = min(distance, im.Maxval)
	}
	return im.withPixels(distances)
}

func statistics(pixels []int, maxval int) string {
	ordered := append([]int(nil), pixels...)
	sort.Ints(ordered)
	counts := make([]int, maxval+1)
	for _, p := range pixels {
		counts[p]++
	}
	mode := 0
	for value := 1; value <= maxval; value++ {
		if counts[value] > counts[mode] {
			mode = value
		}
	}
	n := len(ordered)
	return fmt.Sprintf("min %d max %d mean %d median %d mode %d",
		ordered[0], ordered[n-1], sum(ordered)/n, ordered[(n-1)/2], mode)
}

func dithered(im *Image) *Image {
	errors := append([]int(nil), im.Pixels...)
	pixels := make([]int, len(errors))
	diffusion := [][3]int{{1, 0, 7}, {-1, 1, 3}, {0, 1, 5}, {1, 1, 1}}
	for y := 0; y < im.Height; y++ {
		for x := 0; x < im.Width; x++ {
			i := y*im.Width + x
			old := errors[i]
			next := 0
			if 2*old >= im.Maxval {
				next = im.Maxval
			}
			pixels[i] = next
			err := old - next
			for _, entry := range diffusion {
				nx, ny := x+entry[0], y+entry[1]
				if im.contains(nx, ny) {
					errors[ny*im.Width+nx] += floorDiv(err*entry[2], 16)
				}
			}
		}
	}
	return im.withPixels(pixels)
}

type Command struct {
	Name    string
	Numbers []int
	Slot    string
	Fill    bool
}

type Editor struct {
	Current     *Image
	UndoHistory []*Image
	RedoHistory []*Image
	Slots       map[string]*Image
	Output      []string
}

func newEditor() *Editor {
	return &Editor{Slots: make(map[string]*Image)}
}

func (e *Editor) emit(line string) {
	e.Output = append(e.Output, line)
}

func (e *Editor) parse(words []string) (Command, error) {
	name := words[0]
	pattern, ok := patterns[name]
	if !ok {
		return Command{}, fmt.Errorf("unknown command %s", name)
	}
	args := words[1:]
	fill := (name == "RECT" || name == "CIRCLE") &&
		len(args) == len(pattern)+1 && args[len(args)-1] == "FILL"
	if fill {
		args = args[:len(args)-1]
	}
	if len(args) != len(pattern) {
		return Command{}, fmt.Errorf("bad arguments")
	}
	command := Command{Name: name, Fill: fill}
	for i, word := range args {
		if pattern[i] == 'i' {
			if !integerWord.MatchString(word) {
				return Command{}, fmt.Errorf("bad arguments")
			}
			command.Numbers = append(command.Numbers, number(word))
		} else {
			if !nameWord.MatchString(word) {
				return Command{}, fmt.Errorf("bad arguments")
			}
			command.Slot = word
		}
	}
	return command, nil
}

func (e *Editor) execute(words []string) {
	command, err := e.parse(words)
	if err == nil {
		name := command.Name
		if e.Current == nil {
			switch name {
			case "NEW", "RECALL", "DROP", "SLOTS", "INFO", "UNDO", "REDO":
			default:
				err = fmt.Errorf("no image")
			}
		}
		if err == nil {
			switch name {
			case "RECALL", "DROP", "BLEND", "DIFF", "PASTE":
				if e.Slots[command.Slot] == nil {
					err = fmt.Errorf("no slot %s", command.Slot)
				}
			}
		}
	}
	if err == nil {
		err = e.run(command)
	}
	if err != nil {
		e.emit("error: " + err.Error())
	}
}

func (e *Editor) load(lines []string) {
	image, err := readPGM(lines)
	if err != nil {
		e.emit("error: load: " + err.Error())
		return
	}
	e.replace(image, "loaded")
}

func (e *Editor) replace(im *Image, label string) {
	e.Current = im
	e.UndoHistory = nil
	e.RedoHistory = nil
	e.emit(label + " " + im.summary())
}

func (e *Editor) commit(im *Image, painted *int) {
	e.UndoHistory = append(e.UndoHistory, e.Current)
	e.RedoHistory = nil
	e.Current = im
	line := "ok " + im.summary()
	if painted != nil {
		line += fmt.Sprintf(" painted %d", *painted)
	}
	e.emit(line)
}

func (e *Editor) paint(points []Point, value int) {
	im := e.Current
	marked := make([]bool, len(im.Pixels))
	count := 0
	for _, p := range points {
		if im.contains(p.X, p.Y) {
			i := p.Y*im.Width + p.X
			if !marked[i] {
				marked[i] = true
				count++
			}
		}
	}
	pixels := append([]int(nil), im.Pixels...)
	for i := range pixels {
		if marked[i] {
			pixels[i] = value
		}
	}
	e.commit(im.withPixels(pixels), &count)
}

func (e *Editor) cropArea(args []int) error {
	x, y, w, h := args[0], args[1], args[2], args[3]
	im := e.Current
	if x < 0 || y < 0 || w < 1 || h < 1 ||
		x+w > im.Width || y+h > im.Height {
		return fmt.Errorf("bad value")
	}
	return nil
}

func (e *Editor) matchingSlot(name string) (*Image, error) {
	im, other := e.Current, e.Slots[name]
	if im.Width != other.Width || im.Height != other.Height {
		return nil, fmt.Errorf("size mismatch")
	}
	if im.Maxval != other.Maxval {
		return nil, fmt.Errorf("maxval mismatch")
	}
	return other, nil
}

func (e *Editor) run(command Command) error {
	im := e.Current
	a, name, slot := command.Numbers, command.Name, command.Slot
	maxval := 0
	if im != nil {
		maxval = im.Maxval
	}
	switch name {
	case "NEW":
		w, h, m, value := a[0], a[1], a[2], a[3]
		if w < 1 || w > 64 || h < 1 || h > 64 || m < 1 || m > 255 || value < 0 || value > m {
			return fmt.Errorf("bad value")
		}
		pixels := make([]int, w*h)
		for i := range pixels {
			pixels[i] = value
		}
		e.replace(newImage(w, h, m, pixels), "created")
	case "OUTPUT":
		e.emit("P2")
		e.emit(fmt.Sprintf("%d %d", im.Width, im.Height))
		e.emit(strconv.Itoa(maxval))
		for y := 0; y < im.Height; y++ {
			values := make([]string, im.Width)
			for x, p := range im.row(y) {
				values[x] = strconv.Itoa(p)
			}
			e.emit(strings.Join(values, " "))
		}
	case "INVERT":
		pixels := make([]int, len(im.Pixels))
		for i, p := range im.Pixels {
			pixels[i] = maxval - p
		}
		e.commit(im.withPixels(pixels), nil)
	case "BRIGHTNESS":
		if a[0] < -255 || a[0] > 255 {
			return fmt.Errorf("bad value")
		}
		pixels := make([]int, len(im.Pixels))
		for i, p := range im.Pixels {
			pixels[i] = im.clamp(p + a[0])
		}
		e.commit(im.withPixels(pixels), nil)
	case "CONTRAST":
		num, den := a[0], a[1]
		if num < 0 || num > 100 || den < 1 || den > 100 {
			return fmt.Errorf("bad value")
		}
		center := (maxval + 1) / 2
		pixels := make([]int, len(im.Pixels))
		for i, p := range im.Pixels {
			pixels[i] = im.clamp(center + floorDiv((p-center)*num, den))
		}
		e.commit(im.withPixels(pixels), nil)
	case "THRESHOLD":
		if a[0] < 0 || a[0] > maxval {
			return fmt.Errorf("bad value")
		}
		pixels := make([]int, len(im.Pixels))
		for i, p := range im.Pixels {
			if p >= a[0] {
				pixels[i] = maxval
			}
		}
		e.commit(im.withPixels(pixels), nil)
	case "LEVELS":
		low, high := a[0], a[1]
		if low < 0 || low >= high || high > maxval {
			return fmt.Errorf("bad value")
		}
		pixels := make([]int, len(im.Pixels))
		for i, p := range im.Pixels {
			pixels[i] = im.clamp(floorDiv((p-low)*maxval, high-low))
		}
		e.commit(im.withPixels(pixels), nil)
	case "POSTERIZE":
		levels := a[0]
		if levels < 2 || levels > maxval+1 {
			return fmt.Errorf("bad value")
		}
		pixels := make([]int, len(im.Pixels))
		for i, p := range im.Pixels {
			group := p * levels / (maxval + 1)
			pixels[i] = group * maxval / (levels - 1)
		}
		e.commit(im.withPixels(pixels), nil)
	case "MAXVAL":
		m := a[0]
		if m < 1 || m > 255 {
			return fmt.Errorf("bad value")
		}
		pixels := make([]int, len(im.Pixels))
		for i, p := range im.Pixels {
			pixels[i] = (2*p*m + maxval) / (2 * maxval)
		}
		e.commit(newImage(im.Width, im.Height, m, pixels), nil)
	case "FLIPH", "FLIPV":
		e.commit(transformed(im, im.Width, im.Height, func(x, y int) int {
			if name == "FLIPH" {
				return im.get(im.Width-1-x, y)
			}
			return im.get(x, im.Height-1-y)
		}), nil)
	case "ROTATE":
		if a[0] != 90 && a[0] != 180 && a[0] != 270 {
			return fmt.Errorf("bad value")
		}
		e.commit(rotated(im, a[0]), nil)
	case "CROP":
		if err := e.cropArea(a); err != nil {
			return err
		}
		e.commit(cropped(im, a[0], a[1], a[2], a[3]), nil)
	case "PAD":
		border, fill := a[0], a[1]
		if border < 1 || fill < 0 || fill > maxval {
			return fmt.Errorf("bad value")
		}
		w, h := im.Width+2*border, im.Height+2*border
		if w > 64 || h > 64 {
			return fmt.Errorf("too large")
		}
		e.commit(translated(im, w, h, border, border, fill), nil)
	case "SCALE":
		num, den := a[0], a[1]
		if num < 1 || num > 16 || den < 1 || den > 16 {
			return fmt.Errorf("bad value")
		}
		w, h := im.Width*num/den, im.Height*num/den
		if w == 0 || h == 0 {
			return fmt.Errorf("too small")
		}
		if w > 64 || h > 64 {
			return fmt.Errorf("too large")
		}
		e.commit(scaled(im, w, h, num, den), nil)
	case "SHIFT":
		if !withinLimit(a[0], a[1]) || a[2] < 0 || a[2] > maxval {
			return fmt.Errorf("bad value")
		}
		e.commit(translated(im, im.Width, im.Height, a[0], a[1], a[2]), nil)
	case "TILE":
		if a[0] < 1 || a[1] < 1 {
			return fmt.Errorf("bad value")
		}
		w, h := im.Width*a[0], im.Height*a[1]
		if w > 64 || h > 64 {
			return fmt.Errorf("too large")
		}
		e.commit(transformed(im, w, h, func(x, y int) int {
			return im.get(x%im.Width, y%im.Height)
		}), nil)
	case "BLUR", "GAUSS", "SHARPEN":
		kernel := kernels[name]
		e.commit(convolution(im, kernel.weights, kernel.divisor), nil)
	case "CONVOLVE":
		var kernel [9]int
		for i := range kernel {
			if a[i] < -16 || a[i] > 16 {
				return fmt.Errorf("bad value")
			}
			kernel[i] = a[i]
		}
		if a[9] < 1 || a[9] > 256 {
			return fmt.Errorf("bad value")
		}
		e.commit(convolution(im, kernel, a[9]), nil)
	case "SOBEL":
		e.commit(sobel(im), nil)
	case "MEDIAN", "ERODE", "DILATE":
		rank := 4
		if name == "ERODE" {
			rank = 0
		} else if name == "DILATE" {
			rank = 8
		}
		e.commit(rankFiltered(im, rank), nil)
	case "OPEN":
		e.commit(rankFiltered(rankFiltered(im, 0), 8), nil)
	case "CLOSE":
		e.commit(rankFiltered(rankFiltered(im, 8), 0), nil)
	case "GRADIENT":
		high := rankFiltered(im, 8).Pixels
		low := rankFiltered(im, 0).Pixels
		pixels := make([]int, len(high))
		for i := range pixels {
			pixels[i] = high[i] - low[i]
		}
		e.commit(im.withPixels(pixels), nil)
	case "LINE":
		if !withinLimit(a[:4]...) || a[4] < 0 || a[4] > maxval {
			return fmt.Errorf("bad value")
		}
		e.paint(linePoints(a[0], a[1], a[2], a[3]), a[4])
	case "RECT":
		if !withinLimit(a[0], a[1]) || a[2] < 1 || a[2] > 1000 ||
			a[3] < 1 || a[3] > 1000 || a[4] < 0 || a[4] > maxval {
			return fmt.Errorf("bad value")
		}
		e.paint(rectanglePoints(im, a[0], a[1], a[2], a[3], command.Fill), a[4])
	case "CIRCLE":
		if !withinLimit(a[0], a[1]) || a[2] < 0 || a[2] > 1000 ||
			a[3] < 0 || a[3] > maxval {
			return fmt.Errorf("bad value")
		}
		points := circlePoints(a[0], a[1], a[2])
		if command.Fill {
			points = discPoints(im, points)
		}
		e.paint(points, a[3])
	case "FLOOD":
		if !im.contains(a[0], a[1]) || a[2] < 0 || a[2] > maxval {
			return fmt.Errorf("bad value")
		}
		e.paint(floodPoints(im, a[0], a[1]), a[2])
	case "HISTOGRAM":
		low, high, counts := [16]int{}, [16]int{}, [16]int{}
		used := [16]bool{}
		for p := 0; p <= maxval; p++ {
			bin := p * 16 / (maxval + 1)
			if !used[bin] {
				low[bin] = p
				used[bin] = true
			}
			high[bin] = p
		}
		for _, p := range im.Pixels {
			counts[p*16/(maxval+1)]++
		}
		top := 0
		for _, count := range counts {
			top = max(top, count)
		}
		for bin := 0; bin < 16; bin++ {
			if !used[bin] {
				continue
			}
			e.emit(fmt.Sprintf("%3d-%3d %4d |%s", low[bin], high[bin], counts[bin],
				strings.Repeat("#", counts[bin]*32/top)))
		}
	case "EQUALIZE":
		e.commit(equalized(im), nil)
	case "LABEL":
		if a[0] < 0 || a[0] > maxval {
			return fmt.Errorf("bad value")
		}
		groups := components(im, a[0])
		e.emit(fmt.Sprintf("labels %d", len(groups)))
		for i, group := range groups {
			e.emit(fmt.Sprintf("label %d %s", i+1, componentText(im, a[0], group)))
		}
	case "DISTANCE":
		if a[0] < 0 || a[0] > maxval {
			return fmt.Errorf("bad value")
		}
		e.commit(distanceMap(im, a[0]), nil)
	case "STATS":
		e.emit(statistics(im.Pixels, maxval))
	case "REGION":
		if err := e.cropArea(a); err != nil {
			return err
		}
		e.emit(statistics(cropped(im, a[0], a[1], a[2], a[3]).Pixels, maxval))
	case "DITHER":
		e.commit(dithered(im), nil)
	case "ASCIIART":
		for y := 0; y < im.Height; y++ {
			row := make([]byte, im.Width)
			for x, p := range im.row(y) {
				row[x] = shades[p*len(shades)/(maxval+1)]
			}
			e.emit(string(row))
		}
	case "STORE":
		e.Slots[slot] = im
		e.emit("stored " + slot + " " + im.summary())
	case "RECALL":
		e.replace(e.Slots[slot], "recalled "+slot)
	case "DROP":
		delete(e.Slots, slot)
		e.emit("dropped " + slot)
	case "BLEND":
		num, den := a[0], a[1]
		if num < 0 || num > den || den < 1 || den > 100 {
			return fmt.Errorf("bad value")
		}
		other, err := e.matchingSlot(slot)
		if err != nil {
			return err
		}
		pixels := make([]int, len(im.Pixels))
		for i, p := range im.Pixels {
			pixels[i] = (p*(den-num) + other.Pixels[i]*num) / den
		}
		e.commit(im.withPixels(pixels), nil)
	case "DIFF":
		other, err := e.matchingSlot(slot)
		if err != nil {
			return err
		}
		pixels := make([]int, len(im.Pixels))
		for i, p := range im.Pixels {
			pixels[i] = abs(p - other.Pixels[i])
		}
		e.commit(im.withPixels(pixels), nil)
	case "PASTE":
		if !withinLimit(a...) {
			return fmt.Errorf("bad value")
		}
		other := e.Slots[slot]
		if other.Maxval != maxval {
			return fmt.Errorf("maxval mismatch")
		}
		pixels := append([]int(nil), im.Pixels...)
		painted := 0
		for y := 0; y < other.Height; y++ {
			for x := 0; x < other.Width; x++ {
				nx, ny := a[0]+x, a[1]+y
				if im.contains(nx, ny) {
					pixels[ny*im.Width+nx] = other.get(x, y)
					painted++
				}
			}
		}
		e.commit(im.withPixels(pixels), &painted)
	case "SLOTS":
		names := make([]string, 0, len(e.Slots))
		for name := range e.Slots {
			names = append(names, name)
		}
		sort.Strings(names)
		if len(names) == 0 {
			e.emit("no slots")
		}
		for _, name := range names {
			e.emit(name + " " + e.Slots[name].summary())
		}
	case "INFO":
		summary := "none"
		if im != nil {
			summary = im.summary()
		}
		e.emit(fmt.Sprintf("image %s undo %d redo %d slots %d",
			summary, len(e.UndoHistory), len(e.RedoHistory), len(e.Slots)))
	case "UNDO":
		if len(e.UndoHistory) == 0 {
			return fmt.Errorf("nothing to undo")
		}
		e.RedoHistory = append(e.RedoHistory, im)
		e.Current = e.UndoHistory[len(e.UndoHistory)-1]
		e.UndoHistory = e.UndoHistory[:len(e.UndoHistory)-1]
		e.emit("undo " + e.Current.summary())
	case "REDO":
		if len(e.RedoHistory) == 0 {
			return fmt.Errorf("nothing to redo")
		}
		e.UndoHistory = append(e.UndoHistory, im)
		e.Current = e.RedoHistory[len(e.RedoHistory)-1]
		e.RedoHistory = e.RedoHistory[:len(e.RedoHistory)-1]
		e.emit("redo " + e.Current.summary())
	}
	return nil
}

func main() {
	in := bufio.NewScanner(os.Stdin)
	in.Buffer(make([]byte, 4096), 1<<20)
	if !in.Scan() {
		return
	}
	n := number(strings.TrimSpace(in.Text()))
	editor := newEditor()
	for i := 0; i < n && in.Scan(); i++ {
		words := strings.Fields(in.Text())
		if len(words) == 0 {
			continue
		}
		if words[0] == "LOAD" {
			count := number(words[1])
			lines := make([]string, 0, count)
			for j := 0; j < count && in.Scan(); j++ {
				lines = append(lines, in.Text())
			}
			editor.load(lines)
		} else {
			editor.execute(words)
		}
	}
	fmt.Println(strings.Join(editor.Output, "\n"))
}
