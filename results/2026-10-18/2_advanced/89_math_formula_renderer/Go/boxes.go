package main

import "strings"

type Placement struct {
	Box  *Box
	X, Y int
	Role string
}
type Drawn struct {
	Text string
	X, Y int
}
type Box struct {
	W, H, B     int
	Description string
	Children    []Placement
	Drawn       []Drawn
}

func newBox(w, h, b int, description string) *Box {
	return &Box{W: w, H: h, B: b, Description: description}
}
func (b *Box) add(child *Box, x, y int, role string) {
	b.Children = append(b.Children, Placement{child, x, y, role})
}
func (b *Box) draw(text string, x, y int) { b.Drawn = append(b.Drawn, Drawn{text, x, y}) }
func (b *Box) descent() int               { return b.H - 1 - b.B }

var largeGlyphs = map[string][]string{`\sum`: {`\--`, " > ", "/--"}, `\prod`: {"___", "| |", "| |"}, `\int`: {" /", " |", "/ "}}
var symbolTypes = map[string]string{"+": "binary", "-": "binary", "*": "binary", "=": "relation", "<": "relation", ">": "relation", ":": "relation", "(": "open", "[": "open", ")": "close", "]": "close", "!": "close", ",": "punctuation", ";": "punctuation"}

func delimiterGlyph(value string, height int) []string {
	if value == "." {
		return nil
	}
	actual := value[len(value)-1:]
	glyph := make([]string, height)
	for i := range glyph {
		glyph[i] = actual
	}
	if height >= 2 && (actual == "(" || actual == ")" || actual == "{" || actual == "}") {
		for i := range glyph {
			glyph[i] = "|"
		}
		if actual == "(" || actual == "{" {
			glyph[0] = "/"
			glyph[height-1] = `\`
		} else {
			glyph[0] = `\`
			glyph[height-1] = "/"
		}
		if height >= 3 {
			if actual == "{" {
				glyph[(height-1)/2] = "<"
			}
			if actual == "}" {
				glyph[(height-1)/2] = ">"
			}
		}
	}
	return glyph
}
func drawDelimiter(box *Box, value string, x, height int) {
	for y, character := range delimiterGlyph(value, height) {
		box.draw(character, x, y)
	}
}
func delimiterString(value string) string {
	if value == "." {
		return ""
	}
	return value[len(value)-1:]
}
func center(box *Box, width int) int { return (width - box.W) / 2 }
func delimit(body *Box, left, right string) *Box {
	wl, wr := 1, 1
	if left == "." {
		wl = 0
	}
	if right == "." {
		wr = 0
	}
	out := newBox(wl+body.W+wr, body.H, body.B, "delim "+left+" "+right)
	out.add(body, wl, 0, "")
	drawDelimiter(out, left, 0, body.H)
	drawDelimiter(out, right, wl+body.W, body.H)
	return out
}
func atomBox(n *Node, script bool, references map[string]string) *Box {
	display := n.Value
	description := `atom "` + n.Value + `"`
	if n.Kind == "text" {
		description = `text "` + n.Value + `"`
	}
	if n.Kind == "reference" {
		description = `eqref "` + n.Value + `"`
		var ok bool
		display, ok = references[n.Value]
		if !ok {
			display = "(??)"
		}
	}
	if n.Kind == "command" {
		display = symbolCommands[n.Value].Display
		if glyph, ok := largeGlyphs[n.Value]; ok && !script {
			out := newBox(len(glyph[0]), 3, 1, description)
			for y, line := range glyph {
				out.draw(line, 0, y)
			}
			return out
		}
	}
	out := newBox(len(display), 1, 0, description)
	out.draw(display, 0, 0)
	return out
}
func repeated(c string, n int) string { return strings.Repeat(c, n) }
