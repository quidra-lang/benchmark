package main

import "strings"

type Clause struct {
	attribute, operator string
	mandatory           bool
	literal             Value
}
type TargetLine [][]Clause
type Argument struct {
	name       string
	expression *Expr
}
type Attachment struct {
	kind, effect, id string
	args             []Argument
}
type Element struct {
	kind, id, algorithm, effect string
	parent                      *Element
	children                    []*Element
	targets                     []TargetLine
	condition                   *Expr
	attachments                 []Attachment
}

func parseTarget(s string) TargetLine {
	var out TargetLine
	for _, alt := range strings.Split(s, " | ") {
		var clauses []Clause
		for _, part := range strings.Split(alt, " & ") {
			a := strings.Fields(part)
			ref := a[0]
			mandatory := strings.HasSuffix(ref,
				"!")
			ref = strings.TrimSuffix(ref, "!")
			literal := parseValue(a[2])
			if strings.HasPrefix(a[2], "\"") {
				literal = stringValue(a[2][1 : len(a[2])-1])
			}
			clauses = append(clauses,
				Clause{ref, a[1], mandatory, literal})
		}
		out = append(out, clauses)
	}
	return out
}
func readPolicies() (*Element, []*Element, []*Element) {
	var root *Element
	var stack, elements, rules []*Element
	for _, raw := range readLines("input/policies.txt") {
		line := strings.TrimLeft(raw, " ")
		if line == "" || strings.HasPrefix(line,
			"#") {
			continue
		}
		a := strings.SplitN(line, " ", 2)
		keyword := a[0]
		if keyword == "END" {
			stack = stack[:len(stack)-1]
			continue
		}
		if keyword == "POLICYSET" || keyword == "POLICY" || keyword == "RULE" {
			v := strings.Fields(a[1])
			e := &Element{kind: strings.ToLower(keyword),
				id: v[0]}
			if keyword == "RULE" {
				e.effect = v[1]
				rules = append(rules, e)
			} else {
				e.algorithm = v[1]
			}
			if len(stack) == 0 {
				root = e
			} else {
				e.parent = stack[len(stack)-1]
				e.parent.children = append(e.parent.children,
					e)
			}
			elements = append(elements, e)
			stack = append(stack, e)
			continue
		}
		e := stack[len(stack)-1]
		switch keyword {
		case "TARGET":
			e.targets = append(e.targets,
				parseTarget(a[1]))
		case "CONDITION":
			e.condition = parseExpr(a[1])
		case "OBLIGATION", "ADVICE":
			v := strings.SplitN(a[1],
				" ", 3)
			attachment := Attachment{kind: strings.ToLower(keyword), effect: v[0], id: v[1]}
			if len(v) == 3 {
				for _, part := range strings.Split(v[2], ";") {
					arg := strings.SplitN(strings.TrimSpace(part), "=", 2)
					attachment.args = append(attachment.args,
						Argument{arg[0], parseExpr(arg[1])})
				}
			}
			e.attachments = append(e.attachments, attachment)
		}
	}
	return root,
		elements, rules
}
