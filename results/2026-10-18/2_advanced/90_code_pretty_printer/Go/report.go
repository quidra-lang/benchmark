package main

import (
	"fmt"
	"strings"
)

func docTree(d *Doc, depth int) []string {
	prefix := strings.Repeat(" ", 2*depth)
	out := []string{}
	switch d.Kind {
	case "text", "suffix":
		out = append(out, prefix+d.Kind+` "`+d.Text+`"`)
	case "if_break":
		out = append(out, prefix+`if_break "`+d.Text+`" "`+d.Other+`"`)
	case "line", "softline", "hardline", "break_parent":
		out = append(out, prefix+d.Kind)
	case "concat":
		for _, child := range d.Children {
			out = append(out, docTree(child, depth)...)
		}
	case "group", "nest", "align":
		label := d.Kind
		if d.Kind == "group" {
			label += " " + d.Mode
		}
		if d.Kind == "nest" {
			label += fmt.Sprintf(" %d", d.Number)
		}
		out = append(out, prefix+label)
		out = append(out, docTree(d.Children[0], depth+1)...)
	}
	return out
}

type DiffOp struct {
	Delete bool
	Line   string
}
type Hunk struct {
	Old, New, Deletes, Inserts int
	Operations                 []DiffOp
}

func diffLines(a, b []string) ([]string, int, int) {
	n, m := len(a), len(b)
	lcs := make([][]int, n+1)
	for i := range lcs {
		lcs[i] = make([]int, m+1)
	}
	for i := n - 1; i >= 0; i-- {
		for j := m - 1; j >= 0; j-- {
			if a[i] == b[j] {
				lcs[i][j] = lcs[i+1][j+1] + 1
			} else {
				lcs[i][j] = max(lcs[i+1][j], lcs[i][j+1])
			}
		}
	}
	hunks := []Hunk{}
	i, j := 0, 0
	deletes, inserts := 0, 0
	for i < n || j < m {
		if i < n && j < m && a[i] == b[j] {
			i++
			j++
			continue
		}
		h := Hunk{Old: i, New: j}
		for (i < n || j < m) && !(i < n && j < m && a[i] == b[j]) {
			if j == m || i < n && lcs[i+1][j] >= lcs[i][j+1] {
				h.Operations = append(h.Operations, DiffOp{true, a[i]})
				h.Deletes++
				i++
			} else {
				h.Operations = append(h.Operations, DiffOp{false, b[j]})
				h.Inserts++
				j++
			}
		}
		deletes += h.Deletes
		inserts += h.Inserts
		hunks = append(hunks, h)
	}
	out := []string{fmt.Sprintf("hunks=%d deleted=%d inserted=%d", len(hunks), deletes, inserts)}
	for _, h := range hunks {
		a, b := h.Old, h.New
		if h.Deletes > 0 {
			a++
		}
		if h.Inserts > 0 {
			b++
		}
		out = append(out, fmt.Sprintf("@@ -%d,%d +%d,%d @@", a, h.Deletes, b, h.Inserts))
		for _, op := range h.Operations {
			prefix := "+"
			if op.Delete {
				prefix = "-"
			}
			out = append(out, prefix+op.Line)
		}
	}
	return out, deletes, inserts
}
