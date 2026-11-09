package main

import "strings"

type Command struct {
	Indent int
	Flat   bool
	Doc    *Doc
}

func pushChildren(stack []Command, c Command) []Command {
	for j := len(c.Doc.Children) - 1; j >= 0; j-- {
		stack = append(stack, Command{c.Indent, c.Flat, c.Doc.Children[j]})
	}
	return stack
}
func fits(remaining int, first Command, original []Command) bool {
	if remaining < 0 {
		return false
	}
	stack := []Command{first}
	unused := len(original) - 1
	for len(stack) > 0 || unused >= 0 {
		if len(stack) == 0 {
			stack = append(stack, original[unused])
			unused--
		}
		c := stack[len(stack)-1]
		stack = stack[:len(stack)-1]
		d := c.Doc
		switch d.Kind {
		case "text":
			remaining -= len(d.Text)
		case "if_break":
			value := d.Text
			if c.Flat {
				value = d.Other
			}
			remaining -= len(value)
		case "line":
			if !c.Flat {
				return true
			}
			remaining--
		case "softline":
			if !c.Flat {
				return true
			}
		case "hardline":
			return true
		case "concat":
			stack = pushChildren(stack, c)
		case "group":
			flat := c.Flat
			if d.Forced {
				flat = false
			}
			stack = append(stack, Command{c.Indent, flat, d.Children[0]})
		case "nest", "align":
			stack = append(stack, Command{c.Indent, c.Flat, d.Children[0]})
		}
		if remaining < 0 {
			return false
		}
	}
	return true
}
func printDoc(doc *Doc, width, commentColumn int) []string {
	lines := []string{}
	current := ""
	column := 0
	pending := []string{}
	stack := []Command{{0, false, doc}}
	finalize := func() {
		line := strings.TrimRight(current, " ")
		if len(pending) > 0 {
			comments := strings.Join(pending, " ")
			if commentColumn > 0 && len(line) < commentColumn-1 && commentColumn-1+len(comments) <= width {
				line += strings.Repeat(" ", commentColumn-1-len(line)) + comments
			} else {
				line += " " + comments
			}
		}
		pending = nil
		lines = append(lines, line)
	}
	for len(stack) > 0 {
		c := stack[len(stack)-1]
		stack = stack[:len(stack)-1]
		d := c.Doc
		newline := false
		switch d.Kind {
		case "text":
			current += d.Text
			column += len(d.Text)
		case "if_break":
			value := d.Text
			if c.Flat {
				value = d.Other
			}
			current += value
			column += len(value)
		case "line":
			if c.Flat {
				current += " "
				column++
			} else {
				newline = true
			}
		case "softline":
			newline = !c.Flat
		case "hardline":
			newline = true
		case "concat":
			stack = pushChildren(stack, c)
		case "nest":
			stack = append(stack, Command{c.Indent + d.Number, c.Flat, d.Children[0]})
		case "align":
			stack = append(stack, Command{column, c.Flat, d.Children[0]})
		case "suffix":
			pending = append(pending, d.Text)
		case "group":
			mode := "flat"
			flat := true
			if !c.Flat {
				if d.Forced {
					mode = "forced"
					flat = false
				} else if !fits(width-column, Command{c.Indent, true, d.Children[0]}, stack) {
					mode = "break"
					flat = false
				}
			}
			d.Mode = mode
			stack = append(stack, Command{c.Indent, flat, d.Children[0]})
		}
		if newline {
			finalize()
			current = strings.Repeat(" ", c.Indent)
			column = c.Indent
		}
	}
	finalize()
	return lines
}
