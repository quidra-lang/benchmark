package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

type Formula struct {
	Number     int
	Source     string
	Tokens     []Token
	Nodes      []*Node
	Tag, Label *Token
	TagString  string
	Err        *Issue
	Warnings   []Issue
}
type Typesetter struct {
	Params     map[string]int
	References map[string]string
}

func (t Typesetter) boxes(nodes []*Node, script bool) []*Box {
	out := make([]*Box, len(nodes))
	for i, n := range nodes {
		out[i] = t.typeset(n, script)
	}
	return out
}
func (t Typesetter) typeset(n *Node, script bool) *Box {
	switch n.Kind {
	case "identifier", "number", "symbol", "command", "text", "reference":
		return atomBox(n, script, t.References)
	case "row":
		_, gaps := spacing(n.Items, script, t.Params)
		return rowBox(t.boxes(n.Items, script), gaps, "row", nil)
	case "script":
		base := t.typeset(n.Base, script)
		var sub, sup *Box
		sw, sh, pw, ph := 0, 0, 0, 0
		if n.Sub != nil {
			sub = t.typeset(n.Sub, true)
			sw, sh = sub.W, sub.H
		}
		if n.Sup != nil {
			sup = t.typeset(n.Sup, true)
			pw, ph = sup.W, sup.H
		}
		stacked := !script && (n.Base.Kind == "command" && containsWord(`\sum \prod \lim \max \min`, n.Base.Value) || n.Base.Kind == "accent" && containsWord("overbrace underbrace", n.Base.Value))
		if stacked {
			width := max(base.W, sw, pw)
			out := newBox(width, ph+base.H+sh, ph+base.B, "limits")
			out.add(base, center(base, width), ph, "base: ")
			if sub != nil {
				out.add(sub, center(sub, width), ph+base.H, "sub: ")
			}
			if sup != nil {
				out.add(sup, center(sup, width), 0, "sup: ")
			}
			return out
		}
		bottomOfSup := 0
		if base.B == 0 {
			bottomOfSup = -1
		}
		topSup := bottomOfSup - ph + 1
		topSub := base.H
		if base.descent() > 0 {
			topSub--
		}
		top, bottom := 0, base.H-1
		if sup != nil {
			top = min(0, topSup)
		}
		if sub != nil {
			bottom = max(bottom, topSub+sh-1)
		}
		out := newBox(base.W+max(sw, pw), bottom-top+1, base.B-top, "scripts")
		out.add(base, 0, -top, "base: ")
		if sub != nil {
			out.add(sub, base.W, topSub-top, "sub: ")
		}
		if sup != nil {
			out.add(sup, base.W, topSup-top, "sup: ")
		}
		return out
	case "frac":
		a, b := t.typeset(n.Items[0], script), t.typeset(n.Items[1], script)
		if !script {
			width := max(a.W, b.W) + 2
			out := newBox(width, a.H+1+b.H, a.H, "frac")
			out.add(a, center(a, width), 0, "num: ")
			out.add(b, center(b, width), a.H+1, "den: ")
			out.draw(repeated("-", width), 0, a.H)
			return out
		}
		if n.Items[0].Kind == "row" || n.Items[0].Kind == "frac" {
			a = delimit(a, "(", ")")
		}
		if n.Items[1].Kind == "row" || n.Items[1].Kind == "frac" {
			b = delimit(b, "(", ")")
		}
		slash := newBox(1, 1, 0, `atom "/"`)
		slash.draw("/", 0, 0)
		return rowBox([]*Box{a, slash, b}, []int{0, 0}, "slash", []string{"num: ", "", "den: "})
	case "binom":
		a, b := t.typeset(n.Items[0], script), t.typeset(n.Items[1], script)
		width := max(a.W, b.W)
		height := a.H + 1 + b.H
		out := newBox(width+2, height, a.H, "binom")
		out.add(a, center(a, width)+1, 0, "upper: ")
		out.add(b, center(b, width)+1, a.H+1, "lower: ")
		drawDelimiter(out, "(", 0, height)
		drawDelimiter(out, ")", width+1, height)
		return out
	case "overset", "underset":
		placed, base := t.typeset(n.Items[0], true), t.typeset(n.Items[1], script)
		width := max(placed.W, base.W)
		baseline := base.B
		if n.Kind == "overset" {
			baseline += placed.H
		}
		out := newBox(width, placed.H+base.H, baseline, n.Kind)
		if n.Kind == "overset" {
			out.add(placed, center(placed, width), 0, "over: ")
			out.add(base, center(base, width), placed.H, "base: ")
		} else {
			out.add(base, center(base, width), 0, "base: ")
			out.add(placed, center(placed, width), base.H, "under: ")
		}
		return out
	case "sqrt", "root":
		bodyNode := n.Items[len(n.Items)-1]
		body := t.typeset(bodyNode, script)
		var index *Box
		e, top := 0, 0
		if n.Kind == "root" {
			index = t.typeset(n.Items[0], true)
			e = max(0, index.W-1)
			top = max(0, index.H-body.H)
		}
		k := body.H
		out := newBox(e+k+1+body.W, k+1+top, body.B+1+top, n.Kind)
		out.draw(repeated("_", body.W), e+k+1, top)
		out.draw(`\`, e, k+top)
		for r := 1; r <= k; r++ {
			out.draw("/", e+k-r+1, r+top)
		}
		if index != nil {
			out.add(index, 0, k-index.H+top, "index: ")
			out.add(body, e+k+1, 1+top, "body: ")
		} else {
			out.add(body, e+k+1, 1+top, "")
		}
		return out
	case "delim":
		return delimit(t.typeset(n.Items[0], script), n.Left, n.Right)
	case "matrix":
		rows, cols := len(n.Rows), len(n.Rows[0])
		cells := make([][]*Box, rows)
		widths := make([]int, cols)
		ascents := make([]int, rows)
		descents := make([]int, rows)
		for i, row := range n.Rows {
			cells[i] = t.boxes(row, script)
			for j, b := range cells[i] {
				widths[j] = max(widths[j], b.W)
				ascents[i] = max(ascents[i], b.B)
				descents[i] = max(descents[i], b.descent())
			}
		}
		xs, ys := make([]int, cols), make([]int, rows)
		bodyWidth, bodyHeight := 0, 0
		for j := 0; j < cols; j++ {
			xs[j] = bodyWidth
			bodyWidth += widths[j]
			if j+1 < cols {
				bodyWidth += t.Params["col_gap"]
			}
		}
		for i := 0; i < rows; i++ {
			ys[i] = bodyHeight
			bodyHeight += ascents[i] + descents[i] + 1
			if i+1 < rows {
				bodyHeight += t.Params["row_gap"]
			}
		}
		shift, width := 0, bodyWidth
		if n.Value != "matrix" {
			shift = 2
			width += 2
			if n.Value != "cases" {
				width += 2
			}
		}
		out := newBox(width, bodyHeight, (bodyHeight-1)/2, fmt.Sprintf("%s rows=%d cols=%d", n.Value, rows, cols))
		for i, row := range cells {
			for j, b := range row {
				offset := 0
				if n.Value != "cases" {
					offset = center(b, widths[j])
				}
				out.add(b, xs[j]+offset+shift, ys[i]+ascents[i]-b.B, fmt.Sprintf("cell %d,%d: ", i+1, j+1))
			}
		}
		switch n.Value {
		case "pmatrix":
			drawDelimiter(out, "(", 0, bodyHeight)
			drawDelimiter(out, ")", bodyWidth+3, bodyHeight)
		case "bmatrix":
			drawDelimiter(out, "[", 0, bodyHeight)
			drawDelimiter(out, "]", bodyWidth+3, bodyHeight)
		case "vmatrix":
			drawDelimiter(out, "|", 0, bodyHeight)
			drawDelimiter(out, "|", bodyWidth+3, bodyHeight)
		case "cases":
			drawDelimiter(out, `\{`, 0, bodyHeight)
		}
		return out
	case "accent":
		body := t.typeset(n.Items[0], script)
		width, baseline := body.W, body.B+1
		switch n.Value {
		case "hat", "dot", "tilde":
			width = max(width, 1)
		case "vec":
			width = max(width, 2)
		case "overbrace", "underbrace":
			width += 2
		}
		if n.Value == "underbrace" {
			baseline = body.B
		}
		out := newBox(width, body.H+1, baseline, n.Value)
		switch n.Value {
		case "overline":
			out.draw(repeated("_", body.W), 0, 0)
			out.add(body, 0, 1, "")
		case "hat", "dot", "tilde":
			mark := map[string]string{"hat": "^", "dot": ".", "tilde": "~"}[n.Value]
			out.draw(mark, (width-1)/2, 0)
			out.add(body, 0, 1, "")
		case "vec":
			out.draw(repeated("-", width-1)+">", 0, 0)
			out.add(body, 0, 1, "")
		case "overbrace":
			out.draw("/"+repeated("-", body.W)+`\`, 0, 0)
			out.add(body, 1, 1, "")
		case "underbrace":
			out.add(body, 1, 0, "")
			out.draw(`\`+repeated("-", body.W)+"/", 0, body.H)
		}
		return out
	}
	return newBox(0, 1, 0, "row")
}
func walkNode(n *Node, visit func(*Node)) {
	if n == nil {
		return
	}
	visit(n)
	for _, child := range n.Items {
		walkNode(child, visit)
	}
	walkNode(n.Base, visit)
	walkNode(n.Sub, visit)
	walkNode(n.Sup, visit)
	for _, row := range n.Rows {
		for _, cell := range row {
			walkNode(cell, visit)
		}
	}
}
func collectWarnings(f *Formula, references map[string]string) {
	for _, node := range f.Nodes {
		walkNode(node, func(n *Node) {
			if n.Kind == "identifier" && commandNames[n.Value] {
				f.Warnings = append(f.Warnings, Issue{n.Column, n.Value + " is a command name; write \\" + n.Value})
			}
			if n.Kind == "reference" {
				if _, ok := references[n.Value]; !ok {
					f.Warnings = append(f.Warnings, Issue{n.Column, `undefined reference "` + n.Value + `"`})
				}
			}
			if n.Kind == "delim" && n.Left != "." && n.Right != "." {
				pairs := map[string]string{"(": ")", "[": "]", "|": "|", `\{`: `\}`}
				if pairs[n.Left] != n.Right {
					f.Warnings = append(f.Warnings, Issue{n.RightColumn, "\\left" + n.Left + " closed by \\right" + n.Right})
				}
			}
		})
	}
	sort.Slice(f.Warnings, func(i, j int) bool { return f.Warnings[i].Column < f.Warnings[j].Column })
}
func tree(n *Node) string {
	switch n.Kind {
	case "identifier", "number", "command":
		return n.Value
	case "symbol":
		return "'" + n.Value + "'"
	case "text":
		return `"` + n.Value + `"`
	case "reference":
		return `(eqref "` + n.Value + `")`
	case "script":
		if n.Sub != nil && n.Sup != nil {
			return "(subsup " + tree(n.Base) + " " + tree(n.Sub) + " " + tree(n.Sup) + ")"
		}
		if n.Sub != nil {
			return "(sub " + tree(n.Base) + " " + tree(n.Sub) + ")"
		}
		return "(sup " + tree(n.Base) + " " + tree(n.Sup) + ")"
	case "delim":
		quote := func(d string) string {
			if len(d) == 1 {
				return "'" + d + "'"
			}
			return d
		}
		return "(delim " + quote(n.Left) + " " + quote(n.Right) + " " + tree(n.Items[0]) + ")"
	case "matrix":
		out := "(" + n.Value
		for _, row := range n.Rows {
			parts := []string{}
			for _, cell := range row {
				parts = append(parts, tree(cell))
			}
			out += " [" + strings.Join(parts, " ") + "]"
		}
		return out + ")"
	}
	name := n.Kind
	if name == "accent" {
		name = n.Value
	}
	out := "(" + name
	for _, child := range n.Items {
		out += " " + tree(child)
	}
	return out + ")"
}
func (t Typesetter) linear(n *Node, script bool) string {
	parenthesize := func(child *Node, mode bool, kinds string) string {
		value := t.linear(child, mode)
		if containsWord(kinds, child.Kind) {
			return "(" + value + ")"
		}
		return value
	}
	switch n.Kind {
	case "identifier", "number", "symbol", "text":
		return n.Value
	case "reference":
		if value, ok := t.References[n.Value]; ok {
			return value
		}
		return "(??)"
	case "command":
		return symbolCommands[n.Value].Display
	case "row":
		_, gaps := spacing(n.Items, script, t.Params)
		var b strings.Builder
		for i, child := range n.Items {
			if i > 0 {
				b.WriteString(repeated(" ", gaps[i-1]))
			}
			b.WriteString(t.linear(child, script))
		}
		return b.String()
	case "frac":
		return parenthesize(n.Items[0], script, "row frac") + "/" + parenthesize(n.Items[1], script, "row frac")
	case "binom":
		return "binom(" + t.linear(n.Items[0], script) + ", " + t.linear(n.Items[1], script) + ")"
	case "overset", "underset":
		return n.Kind + "(" + t.linear(n.Items[0], true) + ", " + t.linear(n.Items[1], script) + ")"
	case "script":
		out := parenthesize(n.Base, script, "row frac script")
		if n.Sub != nil {
			out += "_" + parenthesize(n.Sub, true, "row frac")
		}
		if n.Sup != nil {
			out += "^" + parenthesize(n.Sup, true, "row frac")
		}
		return out
	case "sqrt":
		return "sqrt(" + t.linear(n.Items[0], script) + ")"
	case "root":
		return "root(" + t.linear(n.Items[0], true) + ", " + t.linear(n.Items[1], script) + ")"
	case "delim":
		return delimiterString(n.Left) + t.linear(n.Items[0], script) + delimiterString(n.Right)
	case "matrix":
		rows := []string{}
		for _, row := range n.Rows {
			cells := []string{}
			for _, cell := range row {
				cells = append(cells, t.linear(cell, script))
			}
			rows = append(rows, strings.Join(cells, ", "))
		}
		return n.Value + "[" + strings.Join(rows, "; ") + "]"
	case "accent":
		return n.Value + "(" + t.linear(n.Items[0], script) + ")"
	}
	return ""
}

type Line struct{ Start, End, Indent, Width int }

func (t Typesetter) breakLines(nodes []*Node, boxes []*Box, types []ElementTypes, gaps []int, mode int) []Line {
	breaks := map[int]bool{}
	for i := 1; i < len(nodes); i++ {
		if types[i].Left == "relation" || mode >= 2 && nodes[i].Kind == "symbol" && (nodes[i].Value == "+" || nodes[i].Value == "-") && types[i].Left == "binary" || mode == 3 && types[i-1].Right == "punctuation" {
			breaks[i] = true
		}
	}
	widthOf := func(start, end int) int {
		width := 0
		for i := start; i < end; i++ {
			width += boxes[i].W
			if i+1 < end {
				width += gaps[i]
			}
		}
		return width
	}
	out := []Line{}
	alignment, relationWidth := -1, 0
	for start := 0; start < len(nodes); {
		indent := 0
		if start > 0 {
			indent = t.Params["indent"]
			if alignment >= 0 {
				indent = alignment
				if types[start].Left != "relation" {
					indent += relationWidth + t.Params["rel_space"]
				}
			}
		}
		shortest, chosen := -1, -1
		for end := start + 1; end <= len(nodes); end++ {
			if end < len(nodes) && !breaks[end] {
				continue
			}
			if shortest < 0 {
				shortest = end
			}
			if indent+widthOf(start, end) <= t.Params["width"] {
				chosen = end
			}
		}
		if chosen < 0 {
			chosen = shortest
		}
		out = append(out, Line{start, chosen, indent, widthOf(start, chosen)})
		if start == 0 {
			for i := 0; i < chosen; i++ {
				if types[i].Left == "relation" {
					alignment = widthOf(0, i)
					if i > 0 {
						alignment += gaps[i-1]
					}
					relationWidth = boxes[i].W
					break
				}
			}
		}
		start = chosen
	}
	return out
}
func (t Typesetter) placeFormula(f *Formula) ([]Placement, []Line, int, int) {
	types, gaps := spacing(f.Nodes, false, t.Params)
	boxes := t.boxes(f.Nodes, false)
	var lines []Line
	for mode := 1; mode <= 3; mode++ {
		lines = t.breakLines(f.Nodes, boxes, types, gaps, mode)
		fits := true
		for _, line := range lines {
			if line.Indent+line.Width > t.Params["width"] {
				fits = false
			}
		}
		if fits || mode == 3 {
			break
		}
	}
	roots := []Placement{}
	width, height := 0, 0
	for i, line := range lines {
		lineGaps := []int{}
		if line.End-line.Start > 1 {
			lineGaps = gaps[line.Start : line.End-1]
		}
		b := rowBox(boxes[line.Start:line.End], lineGaps, fmt.Sprintf("line %d", i+1), nil)
		roots = append(roots, Placement{Box: b, X: line.Indent, Y: height})
		width = max(width, line.Indent+b.W)
		height += b.H
	}
	if f.TagString != "" {
		tag := newBox(len(f.TagString), 1, 0, `tag "`+f.TagString+`"`)
		tag.draw(f.TagString, 0, 0)
		x := t.Params["width"] - tag.W
		last := roots[len(roots)-1]
		y := last.Y + last.Box.B
		if x < last.X+last.Box.W+2 {
			y = height
			height++
		}
		roots = append(roots, Placement{Box: tag, X: x, Y: y})
		width = max(width, x+tag.W)
	}
	return roots, lines, width, height
}
func inputLines(path string) []string {
	f, err := os.Open(path)
	if err != nil {
		panic(err)
	}
	defer f.Close()
	out := []string{}
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		out = append(out, scanner.Text())
	}
	if err = scanner.Err(); err != nil {
		panic(err)
	}
	return out
}
func writeLines(path string, lines []string) {
	text := ""
	if len(lines) > 0 {
		text = strings.Join(lines, "\n") + "\n"
	}
	if err := os.WriteFile("output/"+path, []byte(text), 0644); err != nil {
		panic(err)
	}
}
func main() {
	params := map[string]int{}
	for _, line := range inputLines("input/params.txt") {
		a := strings.Split(line, " ")
		params[a[0]], _ = strconv.Atoi(a[1])
	}
	formulas := []*Formula{}
	for i, line := range inputLines("input/formulas.txt") {
		f := &Formula{Number: i + 1, Source: line}
		f.Tokens, f.Err = tokenize(line)
		if f.Err == nil {
			f.Err = checkBraces(f.Tokens)
		}
		if f.Err == nil {
			p := &Parser{Tokens: f.Tokens, End: len(line) + 1}
			f.Nodes = p.elements(true, false)
			if p.Err == nil && p.peek().Kind != "eof" {
				p.unexpected(p.peek())
			}
			f.Tag, f.Label, f.Err = p.Tag, p.Label, p.Err
		}
		formulas = append(formulas, f)
	}
	counter := 0
	references := map[string]string{}
	for _, f := range formulas {
		if f.Err != nil {
			continue
		}
		if f.Tag != nil {
			f.TagString = "(" + f.Tag.Value + ")"
		} else if f.Label != nil {
			counter++
			f.TagString = fmt.Sprintf("(%d)", counter)
		}
	}
	for _, f := range formulas {
		if f.Err != nil || f.Label == nil {
			continue
		}
		if _, exists := references[f.Label.Value]; exists {
			f.Warnings = append(f.Warnings, Issue{f.Label.Column, `duplicate label "` + f.Label.Value + `"`})
		} else {
			references[f.Label.Value] = f.TagString
		}
	}
	t := Typesetter{params, references}
	rendered, boxesReport, trees, errors := []string{}, []string{}, []string{}, []string{}
	totalBoxes, maxDepth, valid, warningCount, overfullCount := 0, 0, 0, 0, 0
	kinds := map[string]int{}
	diagnostic := func(f *Formula, issue Issue, warning bool) {
		prefix := ""
		if warning {
			prefix = "warning: "
		}
		errors = append(errors, fmt.Sprintf("formula %d, column %d: %s%s", f.Number, issue.Column, prefix, issue.Message), "  "+f.Source, repeated(" ", issue.Column+1)+"^")
	}
	for i, f := range formulas {
		if i > 0 {
			rendered = append(rendered, "")
		}
		rendered = append(rendered, fmt.Sprintf("formula %d", f.Number))
		if f.Err != nil {
			rendered = append(rendered, "(error)")
			boxesReport = append(boxesReport, fmt.Sprintf("formula %d: error", f.Number))
			trees = append(trees, fmt.Sprintf("formula %d: error", f.Number))
			diagnostic(f, *f.Err, false)
			continue
		}
		valid++
		collectWarnings(f, references)
		warningCount += len(f.Warnings)
		for _, warning := range f.Warnings {
			diagnostic(f, warning, true)
		}
		roots, lines, width, height := t.placeFormula(f)
		rendered = append(rendered, drawCanvas(roots, width, height)...)
		boxLines, depth, counts := describeBoxes(roots)
		totalBoxes += len(boxLines)
		maxDepth = max(maxDepth, depth)
		for kind, count := range counts {
			kinds[kind] += count
		}
		boxesReport = append(boxesReport, fmt.Sprintf("formula %d: lines=%d width=%d height=%d boxes=%d depth=%d", f.Number, len(lines), width, height, len(boxLines), depth))
		boxesReport = append(boxesReport, boxLines...)
		parts := []string{}
		for _, n := range f.Nodes {
			parts = append(parts, tree(n))
		}
		trees = append(trees, fmt.Sprintf("formula %d: %s", f.Number, strings.Join(parts, " ")))
		linear := strings.TrimRight(t.linear(&Node{Kind: "row", Items: f.Nodes}, false), " ")
		linearLine := "  linear:"
		if linear != "" {
			linearLine += " " + linear
		}
		trees = append(trees, linearLine)
		if f.TagString != "" {
			trees = append(trees, "  tag: "+f.TagString)
		}
		for j, line := range lines {
			if line.Indent+line.Width > params["width"] {
				overfullCount++
				errors = append(errors, fmt.Sprintf("formula %d: line %d is overfull (width %d > %d)", f.Number, j+1, line.Indent+line.Width, params["width"]))
			}
		}
	}
	boxesReport = append(boxesReport, fmt.Sprintf("summary: boxes=%d max_depth=%d", totalBoxes, maxDepth))
	names := []string{}
	for name := range kinds {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		boxesReport = append(boxesReport, fmt.Sprintf("  %s: %d", name, kinds[name]))
	}
	errors = append(errors, fmt.Sprintf("formulas=%d rendered=%d errors=%d warnings=%d overfull=%d", len(formulas), valid, len(formulas)-valid, warningCount, overfullCount))
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	writeLines("rendered.txt", rendered)
	writeLines("boxes.txt", boxesReport)
	writeLines("trees.txt", trees)
	writeLines("errors.txt", errors)
}
