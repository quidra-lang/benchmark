package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

type Color [3]int64

type Entry struct {
	name string
	color Color
}

type Spec struct {
	name string
	signature string
	minimum, maximum int
	low, high [4]int64
	keywords string
}

type Arguments struct {
	colors [33]Color
	numbers [33]int64
	keyword int
}

type Group struct {
	color Color
	count int
}

func abs(x int64) int64 {
	if x < 0 { return -x }
	return x
}

func clamp(x int64) int64 { return min(255, max(0, x)) }

func rounded(numerator, denominator int64) int64 {
	numerator = 2*numerator + denominator
	denominator *= 2
	quotient := numerator / denominator
	if numerator < 0 && numerator%denominator != 0 { quotient-- }
	return quotient
}

func away(numerator, denominator int64) int64 {
	if numerator < 0 { return -rounded(-numerator, denominator) }
	return rounded(numerator, denominator)
}

func modulo(value, modulus int64) int64 {
	result := value % modulus
	if result < 0 { result += modulus }
	return result
}

func distance(a, b Color) int64 {
	result := int64(0)
	for j := 0; j < 3; j++ {
		difference := a[j] - b[j]
		result += difference * difference
	}
	return result
}

func extrema(c Color) (int64, int64) {
	return max(c[0], max(c[1], c[2])), min(c[0], min(c[1], c[2]))
}

func hue(c Color) int64 {
	maximum, minimum := extrema(c)
	delta := maximum - minimum
	if delta == 0 { return 0 }
	numerator := int64(0)
	if maximum == c[0] {
		numerator = 60 * (c[1] - c[2])
		if numerator < 0 { numerator += 360 * delta }
	} else if maximum == c[1] {
		numerator = 60*(c[2]-c[0]) + 120*delta
	} else {
		numerator = 60*(c[0]-c[1]) + 240*delta
	}
	return rounded(numerator, delta) % 360
}

func hsl(c Color) [3]int64 {
	maximum, minimum := extrema(c)
	delta := maximum - minimum
	saturation := int64(0)
	if delta != 0 {
		saturation = rounded(100*delta, 255-abs(maximum+minimum-255))
	}
	return [3]int64{hue(c), saturation, rounded(100*(maximum+minimum), 510)}
}

func sector(h int64) Color {
	q, f := h/60, h%60
	x := f
	if q%2 != 0 { x = 60-f }
	switch q {
	case 0: return Color{60, x, 0}
	case 1: return Color{x, 60, 0}
	case 2: return Color{0, 60, x}
	case 3: return Color{0, x, 60}
	case 4: return Color{x, 0, 60}
	default: return Color{60, 0, x}
	}
}

func fromHSL(h, s, l int64) Color {
	chroma := (100-abs(2*l-100)) * s
	offset := 30 * (200*l-chroma)
	result := sector(h)
	for j := range result {
		result[j] = rounded(255*(result[j]*chroma+offset), 600000)
	}
	return result
}

func fromHSV(h, s, v int64) Color {
	chroma := v*s
	offset := 60 * (100*v-chroma)
	result := sector(h)
	for j := range result {
		result[j] = rounded(255*(result[j]*chroma+offset), 600000)
	}
	return result
}

func fromHWB(h, w, k int64) Color {
	if w+k >= 100 {
		value := rounded(255*w, w+k)
		return Color{value, value, value}
	}
	result := sector(h)
	for j := range result {
		result[j] = rounded(255*(result[j]*(100-w-k)+60*w), 6000)
	}
	return result
}

func integerRoot(value int64) int64 {
	low, high := int64(0), int64(1)
	for high*high <= value { high *= 2 }
	for low+1 < high {
		middle := (low+high)/2
		if middle*middle <= value { low = middle } else { high = middle }
	}
	return low
}

func ansiColor(index int) Color {
	levels := [6]int64{0, 95, 135, 175, 215, 255}
	if index < 16 { return builtins[index].color }
	if index >= 232 {
		value := int64(8 + 10*(index-232))
		return Color{value, value, value}
	}
	code := index-16
	return Color{levels[code/36], levels[code/6%6], levels[code%6]}
}

func contrast(a, b Color) (int64, string) {
	luminance := func(c Color) int64 {
		return 2126*c[0]*c[0] + 7152*c[1]*c[1] + 722*c[2]*c[2]
	}
	y1, y2 := luminance(a), luminance(b)
	high, low := max(y1,y2)+32512500, min(y1,y2)+32512500
	verdict := "FAIL"
	if high >= 7*low { verdict = "AAA" } else if 2*high >= 9*low { verdict = "AA" }
	return rounded(100*high, low), verdict
}

func contrastText(c, background Color) string {
	ratio, verdict := contrast(c, background)
	return fmt.Sprintf("%d.%02d %s", ratio/100, ratio%100, verdict)
}

func hex(c Color) string { return fmt.Sprintf("#%02X%02X%02X", c[0], c[1], c[2]) }

func rotate(c Color, degrees int64) Color {
	value := hsl(c)
	return fromHSL(modulo(value[0]+degrees,360), value[1], value[2])
}

func interpolate(first, last Color, position, denominator int64) Color {
	result := first
	for j := range result {
		result[j] += away((last[j]-first[j])*position, denominator)
	}
	return result
}

func blend(mode int, base, top Color) Color {
	if mode >= 13 {
		a, b := hsl(base), hsl(top)
		if mode == 13 || mode == 15 { a[0] = b[0] }
		if mode == 14 || mode == 15 { a[1] = b[1] }
		if mode == 16 { a[2] = b[2] }
		return fromHSL(a[0], a[1], a[2])
	}
	result := base
	for j := range result {
		x, y := base[j], top[j]
		switch mode {
		case 0: result[j] = x*y/255
		case 1: result[j] = 255-(255-x)*(255-y)/255
		case 2, 3:
			condition := x
			if mode == 3 { condition = y }
			if condition < 128 { result[j] = 2*x*y/255
			} else { result[j] = 255-2*(255-x)*(255-y)/255 }
		case 4:
			multiply := x*y/255
			screen := 255-(255-x)*(255-y)/255
			result[j] = ((255-x)*multiply+x*screen)/255
		case 5: result[j] = min(x,y)
		case 6: result[j] = max(x,y)
		case 7: result[j] = abs(x-y)
		case 8: result[j] = x+y-2*x*y/255
		case 9: result[j] = min(255,x+y)
		case 10: result[j] = max(0,x-y)
		case 11:
			result[j] = 255
			if y != 255 { result[j] = min(255,255*x/(255-y)) }
		case 12:
			result[j] = 0
			if y != 0 { result[j] = max(0,255-255*(255-x)/y) }
		}
	}
	return result
}

func mean(colors []Color) Color {
	result := Color{}
	for _, color := range colors {
		for j := range result { result[j] += color[j] }
	}
	for j := range result { result[j] = rounded(result[j],int64(len(colors))) }
	return result
}

func palette(colors []Color, wanted int) []Group {
	boxes := [][]Color{append([]Color(nil),colors...)}
	for len(boxes) < wanted {
		chosen, channel, bestWidth := 0, 0, int64(-1)
		for i, colors := range boxes {
			if len(colors) < 2 { continue }
			width, component := int64(-1), 0
			for j := 0; j < 3; j++ {
				minimum, maximum := int64(255), int64(0)
				for _, color := range colors {
					minimum = min(minimum,color[j])
					maximum = max(maximum,color[j])
				}
				if maximum-minimum > width { width, component = maximum-minimum, j }
			}
			if width > bestWidth { chosen, channel, bestWidth = i, component, width }
		}
		selected := append([]Color(nil),boxes[chosen]...)
		sort.SliceStable(selected,func(i,j int) bool { return selected[i][channel] < selected[j][channel] })
		middle := len(selected)/2
		replacement := make([][]Color,0,len(boxes)+1)
		replacement = append(replacement,boxes[:chosen]...)
		replacement = append(replacement,selected[:middle],selected[middle:])
		replacement = append(replacement,boxes[chosen+1:]...)
		boxes = replacement
	}
	result := make([]Group,len(boxes))
	for i, colors := range boxes { result[i] = Group{mean(colors),len(colors)} }
	return result
}

func kmeans(colors []Color, wanted int) (int, []Group) {
	representatives := palette(colors,wanted)
	for iteration := 1; iteration <= 20; iteration++ {
		sums, counts := make([]Color,wanted), make([]int,wanted)
		for _, color := range colors {
			closest := 0
			for j := 1; j < wanted; j++ {
				if distance(color,representatives[j].color) < distance(color,representatives[closest].color) {
					closest = j
				}
			}
			counts[closest]++
			for j := 0; j < 3; j++ { sums[closest][j] += color[j] }
		}
		unchanged := true
		for i := range representatives {
			representatives[i].count = counts[i]
			if counts[i] == 0 { continue }
			for j := 0; j < 3; j++ { sums[i][j] = rounded(sums[i][j],int64(counts[i])) }
			if sums[i] != representatives[i].color { unchanged = false }
			representatives[i].color = sums[i]
		}
		if unchanged || iteration == 20 { return iteration, representatives }
	}
	panic("unreachable")
}

func parseInteger(text string, low, high int64) (int64, bool) {
	digits := text
	if strings.HasPrefix(text,"-") { digits = text[1:] }
	if len(digits) < 1 || len(digits) > 9 { return 0,false }
	for i := range digits { if digits[i] < '0' || digits[i] > '9' { return 0,false } }
	value, err := strconv.ParseInt(text,10,64)
	return value, err == nil && value >= low && value <= high
}

func validName(text string) bool {
	if len(text) < 1 || len(text) > 12 { return false }
	for i := range text { if text[i] < 'a' || text[i] > 'z' { return false } }
	return true
}

func hexDigit(c byte) (int64, bool) {
	if c >= '0' && c <= '9' { return int64(c-'0'),true }
	if c >= 'a' && c <= 'f' { return int64(c-'a'+10),true }
	if c >= 'A' && c <= 'F' { return int64(c-'A'+10),true }
	return 0,false
}

func parseColor(text string, registry []Entry) (Color, bool) {
	result := Color{}
	if strings.HasPrefix(text,"#") {
		if len(text) != 4 && len(text) != 7 { return result,false }
		for j := range result {
			if len(text) == 4 {
				digit, ok := hexDigit(text[j+1])
				if !ok { return result,false }
				result[j] = 17*digit
			} else {
				hi, ok1 := hexDigit(text[2*j+1])
				lo, ok2 := hexDigit(text[2*j+2])
				if !ok1 || !ok2 { return result,false }
				result[j] = 16*hi+lo
			}
		}
		return result,true
	}
	if strings.HasPrefix(text,"rgb(") {
		if !strings.HasSuffix(text,")") { return result,false }
		parts := strings.Split(text[4:len(text)-1],",")
		if len(parts) != 3 { return result,false }
		for j, part := range parts {
			if len(part) < 1 || len(part) > 3 { return result,false }
			for i := range part { if part[i] < '0' || part[i] > '9' { return result,false } }
			value, ok := parseInteger(part,0,255)
			if !ok { return result,false }
			result[j] = value
		}
		return result,true
	}
	for _, entry := range builtins { if entry.name == text { return entry.color,true } }
	for _, entry := range registry { if entry.name == text { return entry.color,true } }
	return result,false
}

func colorTable(registry []Entry) []Entry {
	result := append([]Entry(nil),builtins[:]...)
	return append(result,registry...)
}

func prepare(spec Spec, words []string, registry []Entry) (Arguments, bool) {
	args := Arguments{}
	if len(words) < spec.minimum || len(words) > spec.maximum { return args,false }
	for i, word := range words {
		kind := byte(0)
		switch spec.signature[0] {
		case '*': kind = 'C'
		case 'P':
			kind = 'C'
			if i == 0 { kind = 'I' }
		default: kind = spec.signature[i]
		}
		switch kind {
		case 'C':
			color, ok := parseColor(word,registry)
			if !ok { return args,false }
			args.colors[i] = color
		case 'I':
			low, high := int64(1), int64(32)
			if spec.signature != "P" { low, high = spec.low[i], spec.high[i] }
			value, ok := parseInteger(word,low,high)
			if !ok { return args,false }
			args.numbers[i] = value
		case 'N':
			if !validName(word) { return args,false }
		case 'K':
			found := false
			for index, candidate := range strings.Split(spec.keywords,"|") {
				if candidate == word { args.keyword, found = index,true; break }
			}
			if !found { return args,false }
		case 'W':
			if len(word) != 6 || !strings.HasPrefix(word,"0x") { return args,false }
			value := int64(0)
			for j := 2; j < 6; j++ {
				digit, ok := hexDigit(word[j])
				if !ok { return args,false }
				value = 16*value+digit
			}
			args.numbers[i] = value
		}
	}
	if spec.signature == "P" && args.numbers[0] > int64(len(words)-1) { return args,false }
	if spec.name == "DEFINE" {
		for _, entry := range builtins { if entry.name == words[0] { return args,false } }
	}
	if spec.name == "UNDEFINE" {
		found := false
		for _, entry := range registry { if entry.name == words[0] { found = true } }
		if !found { return args,false }
	}
	return args,true
}

func model(name string, c Color) string {
	maximum, minimum := extrema(c)
	r, g, b := c[0], c[1], c[2]
	switch name {
	case "HSL":
		value := hsl(c)
		return fmt.Sprintf("hsl(%d,%d%%,%d%%)",value[0],value[1],value[2])
	case "HSV":
		saturation := int64(0)
		if maximum != 0 { saturation = rounded(100*(maximum-minimum),maximum) }
		return fmt.Sprintf("hsv(%d,%d%%,%d%%)",hue(c),saturation,rounded(100*maximum,255))
	case "HWB":
		return fmt.Sprintf("hwb(%d,%d%%,%d%%)",hue(c),rounded(100*minimum,255),rounded(100*(255-maximum),255))
	case "CMYK":
		cyan, magenta, yellow := int64(0), int64(0), int64(0)
		if maximum != 0 {
			cyan = rounded(100*(maximum-r),maximum)
			magenta = rounded(100*(maximum-g),maximum)
			yellow = rounded(100*(maximum-b),maximum)
		}
		return fmt.Sprintf("cmyk(%d%%,%d%%,%d%%,%d%%)",cyan,magenta,yellow,rounded(100*(255-maximum),255))
	case "YCBCR":
		return fmt.Sprintf("ycbcr(%d,%d,%d)",clamp(rounded(299*r+587*g+114*b,1000)),
			clamp(rounded(128000-169*r-331*g+500*b,1000)),clamp(rounded(128000+500*r-419*g-81*b,1000)))
	default:
		return fmt.Sprintf("yiq(%d,%d,%d)",rounded(299*r+587*g+114*b,1000),
			rounded(596*r-274*g-322*b,1000),rounded(211*r-523*g+312*b,1000))
	}
}

var builtins = [24]Entry{
	{"black", Color{0,0,0}},
	{"maroon", Color{128,0,0}},
	{"green", Color{0,128,0}},
	{"olive", Color{128,128,0}},
	{"navy", Color{0,0,128}},
	{"purple", Color{128,0,128}},
	{"teal", Color{0,128,128}},
	{"silver", Color{192,192,192}},
	{"gray", Color{128,128,128}},
	{"red", Color{255,0,0}},
	{"lime", Color{0,255,0}},
	{"yellow", Color{255,255,0}},
	{"blue", Color{0,0,255}},
	{"magenta", Color{255,0,255}},
	{"cyan", Color{0,255,255}},
	{"white", Color{255,255,255}},
	{"orange", Color{255,165,0}},
	{"pink", Color{255,192,203}},
	{"brown", Color{165,42,42}},
	{"gold", Color{255,215,0}},
	{"coral", Color{255,127,80}},
	{"salmon", Color{250,128,114}},
	{"violet", Color{238,130,238}},
	{"indigo", Color{75,0,130}},
}

var specs = [53]Spec{
	{"PARSE", "C", 1, 1, [4]int64{0,0,0,0}, [4]int64{0,0,0,0}, ""},
	{"DEFINE", "NC", 2, 2, [4]int64{0,0,0,0}, [4]int64{0,0,0,0}, ""},
	{"UNDEFINE", "N", 1, 1, [4]int64{0,0,0,0}, [4]int64{0,0,0,0}, ""},
	{"LIST", "", 0, 0, [4]int64{0,0,0,0}, [4]int64{0,0,0,0}, ""},
	{"HSL", "C", 1, 1, [4]int64{0,0,0,0}, [4]int64{0,0,0,0}, ""},
	{"FROMHSL", "III", 3, 3, [4]int64{0,0,0,0}, [4]int64{359,100,100,0}, ""},
	{"HSV", "C", 1, 1, [4]int64{0,0,0,0}, [4]int64{0,0,0,0}, ""},
	{"FROMHSV", "III", 3, 3, [4]int64{0,0,0,0}, [4]int64{359,100,100,0}, ""},
	{"HWB", "C", 1, 1, [4]int64{0,0,0,0}, [4]int64{0,0,0,0}, ""},
	{"FROMHWB", "III", 3, 3, [4]int64{0,0,0,0}, [4]int64{359,100,100,0}, ""},
	{"CMYK", "C", 1, 1, [4]int64{0,0,0,0}, [4]int64{0,0,0,0}, ""},
	{"FROMCMYK", "IIII", 4, 4, [4]int64{0,0,0,0}, [4]int64{100,100,100,100}, ""},
	{"YCBCR", "C", 1, 1, [4]int64{0,0,0,0}, [4]int64{0,0,0,0}, ""},
	{"FROMYCBCR", "III", 3, 3, [4]int64{0,0,0,0}, [4]int64{255,255,255,0}, ""},
	{"YIQ", "C", 1, 1, [4]int64{0,0,0,0}, [4]int64{0,0,0,0}, ""},
	{"FROMYIQ", "III", 3, 3, [4]int64{0,-255,-255,0}, [4]int64{255,255,255,0}, ""},
	{"RGB565", "C", 1, 1, [4]int64{0,0,0,0}, [4]int64{0,0,0,0}, ""},
	{"FROM565", "W", 1, 1, [4]int64{0,0,0,0}, [4]int64{0,0,0,0}, ""},
	{"ANSI", "C", 1, 1, [4]int64{0,0,0,0}, [4]int64{0,0,0,0}, ""},
	{"FROMANSI", "I", 1, 1, [4]int64{0,0,0,0}, [4]int64{255,0,0,0}, ""},
	{"WEBSAFE", "C", 1, 1, [4]int64{0,0,0,0}, [4]int64{0,0,0,0}, ""},
	{"GRAY", "CK", 2, 2, [4]int64{0,0,0,0}, [4]int64{0,0,0,0}, "LUMA|AVERAGE|LIGHTNESS|HSP"},
	{"INVERT", "C", 1, 1, [4]int64{0,0,0,0}, [4]int64{0,0,0,0}, ""},
	{"MIX", "CCI", 3, 3, [4]int64{0,0,0,0}, [4]int64{0,0,100,0}, ""},
	{"MIXHSL", "CCI", 3, 3, [4]int64{0,0,0,0}, [4]int64{0,0,100,0}, ""},
	{"GRADIENT", "CCI", 3, 3, [4]int64{0,0,2,0}, [4]int64{0,0,16,0}, ""},
	{"TINTS", "CI", 2, 2, [4]int64{0,1,0,0}, [4]int64{0,10,0,0}, ""},
	{"SHADES", "CI", 2, 2, [4]int64{0,1,0,0}, [4]int64{0,10,0,0}, ""},
	{"TONES", "CI", 2, 2, [4]int64{0,1,0,0}, [4]int64{0,10,0,0}, ""},
	{"BLEND", "KCC", 3, 3, [4]int64{0,0,0,0}, [4]int64{0,0,0,0}, "MULTIPLY|SCREEN|OVERLAY|HARDLIGHT|SOFTLIGHT|DARKEN|LIGHTEN|DIFFERENCE|EXCLUSION|ADD|SUBTRACT|COLORDODGE|COLORBURN|HUE|SATURATION|COLOR|LUMINOSITY"},
	{"ALPHA", "CICI", 4, 4, [4]int64{0,0,0,0}, [4]int64{0,100,0,100}, ""},
	{"SIMULATE", "CK", 2, 2, [4]int64{0,0,0,0}, [4]int64{0,0,0,0}, "PROTANOPIA|DEUTERANOPIA|TRITANOPIA|ACHROMATOPSIA"},
	{"ROTATE", "CI", 2, 2, [4]int64{0,-720,0,0}, [4]int64{0,720,0,0}, ""},
	{"COMPLEMENT", "C", 1, 1, [4]int64{0,0,0,0}, [4]int64{0,0,0,0}, ""},
	{"TRIADIC", "C", 1, 1, [4]int64{0,0,0,0}, [4]int64{0,0,0,0}, ""},
	{"TETRADIC", "C", 1, 1, [4]int64{0,0,0,0}, [4]int64{0,0,0,0}, ""},
	{"SPLITCOMP", "C", 1, 1, [4]int64{0,0,0,0}, [4]int64{0,0,0,0}, ""},
	{"ANALOGOUS", "CII", 3, 3, [4]int64{0,1,1,0}, [4]int64{0,6,60,0}, ""},
	{"LIGHTEN", "CI", 2, 2, [4]int64{0,0,0,0}, [4]int64{0,100,0,0}, ""},
	{"DARKEN", "CI", 2, 2, [4]int64{0,0,0,0}, [4]int64{0,100,0,0}, ""},
	{"SATURATE", "CI", 2, 2, [4]int64{0,0,0,0}, [4]int64{0,100,0,0}, ""},
	{"DESATURATE", "CI", 2, 2, [4]int64{0,0,0,0}, [4]int64{0,100,0,0}, ""},
	{"NEAREST", "C", 1, 1, [4]int64{0,0,0,0}, [4]int64{0,0,0,0}, ""},
	{"DISTANCE", "CC", 2, 2, [4]int64{0,0,0,0}, [4]int64{0,0,0,0}, ""},
	{"CONTRAST", "CC", 2, 2, [4]int64{0,0,0,0}, [4]int64{0,0,0,0}, ""},
	{"ACCESSIBLE", "CC", 2, 2, [4]int64{0,0,0,0}, [4]int64{0,0,0,0}, ""},
	{"BEST", "*", 2, 33, [4]int64{0,0,0,0}, [4]int64{0,0,0,0}, ""},
	{"DESCRIBE", "C", 1, 1, [4]int64{0,0,0,0}, [4]int64{0,0,0,0}, ""},
	{"PALETTE", "P", 2, 33, [4]int64{0,0,0,0}, [4]int64{0,0,0,0}, ""},
	{"KMEANS", "P", 2, 33, [4]int64{0,0,0,0}, [4]int64{0,0,0,0}, ""},
	{"SORT", "*", 1, 32, [4]int64{0,0,0,0}, [4]int64{0,0,0,0}, ""},
	{"DITHER", "*", 1, 32, [4]int64{0,0,0,0}, [4]int64{0,0,0,0}, ""},
	{"RANDOM", "II", 2, 2, [4]int64{1,1,0,0}, [4]int64{999999999,16,0,0}, ""},
}

func run(line string, registry *[]Entry) (string, bool) {
	tokens := strings.Split(line," ")
	var spec *Spec
	for i := range specs {
		if specs[i].name == tokens[0] { spec = &specs[i]; break }
	}
	if spec == nil { return "",false }
	words := tokens[1:]
	args, valid := prepare(*spec,words,*registry)
	if !valid { return "",false }
	c := args.colors[0]
	a, b, d := args.numbers[0], args.numbers[1], args.numbers[2]
	output := []string{}
	switch spec.name {
	case "DEFINE":
		output = append(output,fmt.Sprintf("%s %s",words[0],hex(args.colors[1])))
		index := -1
		for i, entry := range *registry { if entry.name == words[0] { index = i; break } }
		if index >= 0 { (*registry)[index].color = args.colors[1]
		} else { *registry = append(*registry,Entry{words[0],args.colors[1]}) }
	case "UNDEFINE":
		output = append(output,words[0]+" removed")
		for i, entry := range *registry {
			if entry.name == words[0] {
				*registry = append((*registry)[:i],(*registry)[i+1:]...)
				break
			}
		}
	case "LIST":
		sorted := append([]Entry(nil),(*registry)...)
		sort.Slice(sorted,func(i,j int) bool { return sorted[i].name < sorted[j].name })
		for _, entry := range sorted { output = append(output,entry.name+"="+hex(entry.color)) }
		if len(output) == 0 { output = append(output,"NONE") }
	case "PARSE":
		output = append(output,hex(c),fmt.Sprintf("rgb(%d,%d,%d)",c[0],c[1],c[2]))
		for _, name := range []string{"HSL","HSV","HWB","CMYK","YCBCR","YIQ"} {
			output = append(output,model(name,c))
		}
		name := "-"
		for _, entry := range colorTable(*registry) {
			if entry.color == c { name = entry.name; break }
		}
		output = append(output,name)
	case "HSL", "HSV", "HWB", "CMYK", "YCBCR", "YIQ":
		output = append(output,model(spec.name,c))
	case "FROMHSL": output = append(output,hex(fromHSL(a,b,d)))
	case "FROMHSV": output = append(output,hex(fromHSV(a,b,d)))
	case "FROMHWB": output = append(output,hex(fromHWB(a,b,d)))
	case "FROMCMYK":
		result := Color{}
		for j := range result { result[j] = rounded(255*(100-args.numbers[j])*(100-args.numbers[3]),10000) }
		output = append(output,hex(result))
	case "FROMYCBCR":
		output = append(output,hex(Color{
			clamp(rounded(1000*a+1402*(d-128),1000)),
			clamp(rounded(1000*a-344*(b-128)-714*(d-128),1000)),
			clamp(rounded(1000*a+1772*(b-128),1000)),
		}))
	case "FROMYIQ":
		output = append(output,hex(Color{
			clamp(rounded(1000*a+956*b+619*d,1000)),
			clamp(rounded(1000*a-272*b-647*d,1000)),
			clamp(rounded(1000*a-1106*b+1703*d,1000)),
		}))
	case "RGB565":
		code := 2048*rounded(31*c[0],255)+32*rounded(63*c[1],255)+rounded(31*c[2],255)
		output = append(output,fmt.Sprintf("0x%04X",code))
	case "FROM565":
		output = append(output,hex(Color{
			rounded(255*(a/2048),31),rounded(255*(a/32%64),63),rounded(255*(a%32),31),
		}))
	case "FROMANSI": output = append(output,hex(ansiColor(int(a))))
	case "ANSI":
		best := 16
		for i := 17; i <= 255; i++ {
			if distance(c,ansiColor(i)) < distance(c,ansiColor(best)) { best = i }
		}
		output = append(output,fmt.Sprintf("%d %s %d",best,hex(ansiColor(best)),distance(c,ansiColor(best))))
	case "WEBSAFE":
		result := c
		for j := range result { result[j] = 51*rounded(c[j],51) }
		output = append(output,hex(result))
	case "GRAY":
		maximum, minimum := extrema(c)
		value := int64(0)
		switch args.keyword {
		case 0: value = rounded(299*c[0]+587*c[1]+114*c[2],1000)
		case 1: value = rounded(c[0]+c[1]+c[2],3)
		case 2: value = rounded(maximum+minimum,2)
		case 3: value = integerRoot((299*c[0]*c[0]+587*c[1]*c[1]+114*c[2]*c[2])/1000)
		}
		output = append(output,hex(Color{value,value,value}))
	case "INVERT": output = append(output,hex(Color{255-c[0],255-c[1],255-c[2]}))
	case "MIX":
		result := c
		for j := range result { result[j] = rounded(c[j]*(100-d)+args.colors[1][j]*d,100) }
		output = append(output,hex(result))
	case "MIXHSL":
		first, last := hsl(c), hsl(args.colors[1])
		delta := modulo(last[0]-first[0],360)
		if delta > 180 { delta -= 360 }
		output = append(output,hex(fromHSL(modulo(first[0]+away(delta*d,100),360),
			first[1]+away((last[1]-first[1])*d,100),first[2]+away((last[2]-first[2])*d,100))))
	case "GRADIENT":
		for i := int64(0); i < d; i++ { output = append(output,hex(interpolate(c,args.colors[1],i,d-1))) }
	case "TINTS", "SHADES", "TONES":
		target := int64(128)
		if spec.name == "TINTS" { target = 255 } else if spec.name == "SHADES" { target = 0 }
		for i := int64(1); i <= b; i++ { output = append(output,hex(interpolate(c,Color{target,target,target},i,b+1))) }
	case "BLEND": output = append(output,hex(blend(args.keyword,args.colors[1],args.colors[2])))
	case "ALPHA":
		q := args.numbers[3]
		alpha := 100*b+q*(100-b)
		result := Color{}
		if alpha > 0 {
			for j := range result { result[j] = rounded(100*b*c[j]+q*(100-b)*args.colors[2][j],alpha) }
		}
		output = append(output,fmt.Sprintf("%s %d%%",hex(result),rounded(alpha,100)))
	case "SIMULATE":
		coefficients := [4][3][3]int64{
			{{567,433,0},{558,442,0},{0,242,758}},
			{{625,375,0},{700,300,0},{0,300,700}},
			{{950,50,0},{0,433,567},{0,475,525}},
			{{299,587,114},{299,587,114},{299,587,114}},
		}
		result := Color{}
		for j := range result {
			sum := int64(0)
			for k := 0; k < 3; k++ { sum += coefficients[args.keyword][j][k]*c[k] }
			result[j] = rounded(sum,1000)
		}
		output = append(output,hex(result))
	case "ROTATE": output = append(output,hex(rotate(c,b)))
	case "COMPLEMENT": output = append(output,hex(rotate(c,180)))
	case "TRIADIC":
		for _, shift := range []int64{120,240} { output = append(output,hex(rotate(c,shift))) }
	case "TETRADIC":
		for _, shift := range []int64{90,180,270} { output = append(output,hex(rotate(c,shift))) }
	case "SPLITCOMP":
		for _, shift := range []int64{150,210} { output = append(output,hex(rotate(c,shift))) }
	case "ANALOGOUS":
		for i := -b; i <= b; i++ { if i != 0 { output = append(output,hex(rotate(c,i*d))) } }
	case "LIGHTEN", "DARKEN", "SATURATE", "DESATURATE":
		value := hsl(c)
		switch spec.name {
		case "LIGHTEN": value[2] = min(100,value[2]+b)
		case "DARKEN": value[2] = max(0,value[2]-b)
		case "SATURATE": value[1] = min(100,value[1]+b)
		case "DESATURATE": value[1] = max(0,value[1]-b)
		}
		output = append(output,hex(fromHSL(value[0],value[1],value[2])))
	case "NEAREST":
		entries := colorTable(*registry)
		best := 0
		for i := 1; i < len(entries); i++ {
			if distance(c,entries[i].color) < distance(c,entries[best].color) { best = i }
		}
		entry := entries[best]
		output = append(output,fmt.Sprintf("%s %s %d",entry.name,hex(entry.color),distance(c,entry.color)))
	case "DISTANCE":
		other := args.colors[1]
		r, g, blue := c[0]-other[0], c[1]-other[1], c[2]-other[2]
		weight := (1024+c[0]+other[0])*r*r + 2048*g*g + (1534-c[0]-other[0])*blue*blue
		output = append(output,fmt.Sprintf("%d %d",distance(c,other),integerRoot(weight/512)))
	case "CONTRAST": output = append(output,contrastText(c,args.colors[1]))
	case "ACCESSIBLE":
		background, result := args.colors[1], c
		_, verdict := contrast(c,background)
		if verdict == "FAIL" {
			value, found := hsl(c), false
			for step := int64(1); step <= 100 && !found; step++ {
				for _, sign := range []int64{-1,1} {
					lightness := value[2]+sign*step
					if lightness < 0 || lightness > 100 { continue }
					candidate := fromHSL(value[0],value[1],lightness)
					_, verdict := contrast(candidate,background)
					if verdict != "FAIL" { result, found = candidate,true; break }
				}
			}
		}
		output = append(output,hex(result)+" "+contrastText(result,background))
	case "BEST":
		best := 1
		bestRatio, _ := contrast(args.colors[best],c)
		for i := 2; i < len(words); i++ {
			ratio, _ := contrast(args.colors[i],c)
			if ratio > bestRatio { best, bestRatio = i,ratio }
		}
		output = append(output,hex(args.colors[best])+" "+contrastText(args.colors[best],c))
	case "DESCRIBE":
		value := hsl(c)
		h, s, l := value[0], value[1], value[2]
		if l <= 5 { output = append(output,"black")
		} else if l >= 95 { output = append(output,"white")
		} else {
			lightness := "very light"
			switch {
			case l <= 20: lightness = "very dark"
			case l <= 40: lightness = "dark"
			case l <= 60: lightness = "medium"
			case l <= 80: lightness = "light"
			}
			if s < 10 { output = append(output,lightness+" gray")
			} else {
				names := []string{"red","orange","yellow","chartreuse","green","spring-green",
					"cyan","azure","blue","violet","magenta","rose"}
				saturation := "vivid"
				if s < 40 { saturation = "muted" } else if s < 80 { saturation = "moderate" }
				output = append(output,lightness+" "+saturation+" "+names[(h+15)%360/30])
			}
		}
	case "PALETTE", "KMEANS":
		colors := args.colors[1:len(words)]
		var groups []Group
		if spec.name == "PALETTE" { groups = palette(colors,int(a))
		} else {
			iterations, result := kmeans(colors,int(a))
			groups = result
			output = append(output,strconv.Itoa(iterations))
		}
		for _, group := range groups { output = append(output,fmt.Sprintf("%s:%d",hex(group.color),group.count)) }
	case "SORT":
		colors := append([]Color(nil),args.colors[:len(words)]...)
		sort.SliceStable(colors,func(i,j int) bool {
			a, b := hsl(colors[i]), hsl(colors[j])
			for k := 0; k < 3; k++ { if a[k] != b[k] { return a[k] < b[k] } }
			return false
		})
		for _, color := range colors { output = append(output,hex(color)) }
	case "DITHER":
		error := Color{}
		for _, color := range args.colors[:len(words)] {
			target := color
			for j := range target { target[j] = clamp(target[j]+error[j]) }
			best := 0
			for i := 1; i < 16; i++ {
				if distance(target,builtins[i].color) < distance(target,builtins[best].color) { best = i }
			}
			output = append(output,builtins[best].name)
			for j := range error { error[j] = target[j]-builtins[best].color[j] }
		}
	case "RANDOM":
		state := a
		for i := int64(0); i < b; i++ {
			state = state*48271%2147483647
			h := state%360
			state = state*48271%2147483647
			s := 40+state%61
			state = state*48271%2147483647
			l := 25+state%51
			output = append(output,hex(fromHSL(h,s,l)))
		}
	}
	return strings.Join(output," "),true
}

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	if !scanner.Scan() { return }
	count, _ := strconv.Atoi(scanner.Text())
	writer := bufio.NewWriter(os.Stdout)
	defer writer.Flush()
	registry := []Entry{}
	for i := 0; i < count; i++ {
		scanner.Scan()
		result, valid := run(scanner.Text(),&registry)
		if !valid { result = "INVALID" }
		fmt.Fprintln(writer,result)
	}
}
