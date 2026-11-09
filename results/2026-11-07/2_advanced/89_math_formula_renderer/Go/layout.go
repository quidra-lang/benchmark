package main

type ElementTypes struct{ Left, Right string }

func elementTypes(n *Node) ElementTypes {
	kind := "ordinary"
	switch n.Kind {
	case "symbol":
		if value, ok := symbolTypes[n.Value]; ok {
			kind = value
		}
	case "command":
		kind = symbolCommands[n.Value].Type
	case "delim":
		return ElementTypes{"open", "close"}
	case "script":
		return elementTypes(n.Base)
	case "overset", "underset":
		return elementTypes(n.Items[1])
	}
	return ElementTypes{kind, kind}
}
func convertedTypes(nodes []*Node) []ElementTypes {
	out := make([]ElementTypes, len(nodes))
	for i, n := range nodes {
		out[i] = elementTypes(n)
	}
	for i := range out {
		if out[i].Left == "binary" && (i == 0 || containsWord("binary operator relation open punctuation", out[i-1].Right)) {
			out[i] = ElementTypes{"ordinary", "ordinary"}
		}
		if i > 0 && containsWord("relation close punctuation", out[i].Left) && out[i-1].Right == "binary" {
			out[i-1] = ElementTypes{"ordinary", "ordinary"}
		}
	}
	if len(out) > 0 && out[len(out)-1].Right == "binary" {
		out[len(out)-1] = ElementTypes{"ordinary", "ordinary"}
	}
	return out
}
func wordElement(n *Node) bool {
	if n.Kind == "script" {
		return wordElement(n.Base)
	}
	return n.Kind == "command" && (greek[n.Value[1:]] || n.Value == `\infty`)
}
func alphanumeric(n *Node) bool {
	if n.Kind == "identifier" || n.Kind == "number" || wordElement(n) {
		return true
	}
	if n.Kind == "script" {
		return alphanumeric(n.Base)
	}
	return n.Kind == "accent" && containsWord("overline hat vec dot tilde", n.Value) && alphanumeric(n.Items[0])
}

var typeIndex = map[string]int{"ordinary": 0, "operator": 1, "binary": 2, "relation": 3, "open": 4, "close": 5, "punctuation": 6}
var spacingTable = [7][7]string{{"0", "1", "B", "R", "0", "0", "0"}, {"1", "1", "-", "R", "0", "0", "0"}, {"B", "B", "-", "-", "B", "-", "-"}, {"R", "R", "-", "0", "R", "0", "0"}, {"0", "0", "-", "0", "0", "0", "0"}, {"0", "1", "B", "R", "0", "0", "0"}, {"P", "P", "-", "P", "P", "P", "P"}}

func spacing(nodes []*Node, script bool, params map[string]int) ([]ElementTypes, []int) {
	types := convertedTypes(nodes)
	gaps := make([]int, max(0, len(nodes)-1))
	for i := range gaps {
		if alphanumeric(nodes[i]) && alphanumeric(nodes[i+1]) && (wordElement(nodes[i]) || wordElement(nodes[i+1])) {
			gaps[i] = 1
			continue
		}
		entry := spacingTable[typeIndex[types[i].Right]][typeIndex[types[i+1].Left]]
		if entry == "1" {
			gaps[i] = 1
		}
		if !script {
			switch entry {
			case "B":
				gaps[i] = params["bin_space"]
			case "R":
				gaps[i] = params["rel_space"]
			case "P":
				gaps[i] = params["punct_space"]
			}
		}
	}
	return types, gaps
}
func rowBox(children []*Box, gaps []int, description string, roles []string) *Box {
	ascent, descent, width := 0, 0, 0
	for _, child := range children {
		ascent = max(ascent, child.B)
		descent = max(descent, child.descent())
		width += child.W
	}
	for _, gap := range gaps {
		width += gap
	}
	out := newBox(width, ascent+descent+1, ascent, description)
	x := 0
	for i, child := range children {
		role := ""
		if roles != nil {
			role = roles[i]
		}
		out.add(child, x, ascent-child.B, role)
		x += child.W
		if i < len(gaps) {
			x += gaps[i]
		}
	}
	return out
}
