package main

import (
	"fmt"
	"strings"
)

type TreeNode struct {
	Symbol, Mark string
	Children     []*TreeNode
}
type InputToken struct {
	Name     string
	Position int
}
type StackItem struct {
	Symbol string
	Node   *TreeNode
}
type ParseResult struct {
	Root                                            *TreeNode
	Trace                                           [][4]string
	LeftParse                                       []int
	Errors, UnknownErrors, Original                 []string
	Predicts, Matches, Skip, Pop, Missing, MaxStack int
	Accepted, Language                              bool
}

func treeLabel(node *TreeNode) string {
	if node.Mark == "" {
		return node.Symbol
	}
	return node.Symbol + " (" + node.Mark + ")"
}
func parseTokens(tokens []InputToken, g Grammar, sets Sets, table ParseTable) ParseResult {
	input := append(append([]InputToken{}, tokens...), InputToken{"$", len(tokens) + 1})
	root := &TreeNode{Symbol: g.Start}
	stack := []StackItem{{Symbol: "$"}, {g.Start, root}}
	out := ParseResult{Root: root}
	cursor := 0
	for step := 1; ; step++ {
		item := stack[len(stack)-1]
		top, node := item.Symbol, item.Node
		current := input[cursor]
		out.MaxStack = max(out.MaxStack, len(stack))
		symbols := []string{}
		for _, v := range stack {
			symbols = append(symbols, v.Symbol)
		}
		remaining := []string{}
		for _, v := range input[cursor:] {
			remaining = append(remaining, v.Name)
		}
		action, event := "", ""
		terminate := false
		switch {
		case top == "$" && current.Name == "$":
			action = "accept"
			terminate = true
		case top == "$":
			action = "error: skip " + current.Name
			event = "skip"
			cursor++
			out.Skip++
		case !isNonterminal(top):
			if top == current.Name {
				action = "match " + current.Name
				stack = stack[:len(stack)-1]
				cursor++
				out.Matches++
			} else {
				action = "error: missing " + top
				node.Mark = "missing"
				stack = stack[:len(stack)-1]
				out.Missing++
				event = "missing"
			}
		case table.Choices[CellKey{top, current.Name}] > 0:
			number := table.Choices[CellKey{top, current.Name}]
			p := table.Productions[number-1]
			action = fmt.Sprintf("predict %d: %s", number, p.Notation)
			out.LeftParse = append(out.LeftParse, number)
			stack = stack[:len(stack)-1]
			children := []*TreeNode{}
			for _, s := range p.RHS {
				children = append(children, &TreeNode{Symbol: s})
			}
			if len(children) == 0 {
				node.Children = append(node.Children, &TreeNode{Symbol: "%empty"})
			} else {
				node.Children = append(node.Children, children...)
				for i := len(children) - 1; i >= 0; i-- {
					stack = append(stack, StackItem{children[i].Symbol, children[i]})
				}
			}
			out.Predicts++
		case current.Name == "$" || sets.Follow[top][current.Name]:
			action = "error: pop " + top
			node.Mark = "error"
			stack = stack[:len(stack)-1]
			out.Pop++
			event = "pop"
		default:
			action = "error: skip " + current.Name
			cursor++
			out.Skip++
			event = "skip"
		}
		out.Trace = append(out.Trace, [4]string{fmt.Sprint(step), strings.Join(symbols, " "), strings.Join(remaining, " "), action})
		if event != "" {
			unexpected := "end of input"
			if current.Name != "$" {
				unexpected = fmt.Sprintf("\"%s\" at token %d", current.Name, current.Position)
			}
			expected := ""
			if isNonterminal(top) {
				values := []string{}
				for _, t := range append(append([]string{}, sets.Terminals...), "$") {
					if table.Choices[CellKey{top, t}] > 0 {
						if t == "$" {
							values = append(values, t)
						} else {
							values = append(values, "\""+t+"\"")
						}
					}
				}
				expected = strings.Join(values, " ")
			} else if top == "$" {
				expected = "$"
			} else {
				expected = "\"" + top + "\""
			}
			recovery := "skipped \"" + current.Name + "\""
			if event == "pop" {
				recovery = "popped " + top
			}
			if event == "missing" {
				recovery = "inserted \"" + top + "\""
			}
			out.Errors = append(out.Errors, fmt.Sprintf("step %d: unexpected %s; expected %s; %s", step, unexpected, expected, recovery))
		}
		if terminate {
			break
		}
	}
	return out
}
