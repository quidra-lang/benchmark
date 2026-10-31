package main

import (
	"fmt"
	"strings"
)

func displayLine(pieces []string, slack int, alignment string, last bool) string {
	shown := make([]string, len(pieces))
	for i, p := range pieces {
		shown[i] = strings.ReplaceAll(p, "~", " ")
	}
	text := strings.Join(shown, " ")
	if slack <= 0 {
		return text
	}
	gaps := len(pieces) - 1
	if alignment == "justify" && !last && gaps > 0 {
		q, r := slack/gaps, slack%gaps
		var b strings.Builder
		b.WriteString(shown[0])
		for i, p := range shown[1:] {
			spaces := q + 1
			if i < r {
				spaces++
			}
			b.WriteString(strings.Repeat(" ", spaces))
			b.WriteString(p)
		}
		return b.String()
	}
	if alignment == "right" {
		return strings.Repeat(" ", slack) + text
	}
	if alignment == "center" {
		return strings.Repeat(" ", slack/2) + text
	}
	return text
}
func formatTable(rows [][]string, columns, caption, number string) []string {
	widths := make([]int, len(columns))
	for _, row := range rows {
		for i, text := range row {
			widths[i] = max(widths[i], len(text))
		}
	}
	lines := []string{}
	if caption != "" {
		lines = append(lines, "Table "+number+". "+caption)
	}
	for ri, row := range rows {
		cells := []string{}
		for i, text := range row {
			missing := widths[i] - len(text)
			before := 0
			if columns[i] == 'r' {
				before = missing
			} else if columns[i] == 'c' {
				before = missing / 2
			}
			cells = append(cells, strings.Repeat(" ", before)+text+strings.Repeat(" ", missing-before))
		}
		lines = append(lines, strings.TrimRight(strings.Join(cells, " | "), " "))
		if ri == 0 {
			rules := []string{}
			for _, width := range widths {
				rules = append(rules, strings.Repeat("-", width))
			}
			lines = append(lines, strings.Join(rules, "-+-"))
		}
	}
	return lines
}
func runningHead(fields [3]string, values [4]string, width, serial int) string {
	names := [4]string{"page", "pages", "chapter", "section"}
	expanded := fields
	for i, field := range fields {
		for j, name := range names {
			field = strings.ReplaceAll(field, "{"+name+"}", values[j])
		}
		expanded[i] = field
	}
	left, center, right := expanded[0], expanded[1], expanded[2]
	if serial%2 == 0 {
		left, right = right, left
	}
	line := []byte(strings.Repeat(" ", width))
	for _, p := range []struct {
		Start int
		Text  string
	}{{0, left}, {(width - len(center)) / 2, center}, {width - len(right), right}} {
		copy(line[p.Start:], p.Text)
	}
	return strings.TrimRight(string(line), " ")
}
func pagesText(pages []*Page) string {
	lines := []string{}
	for _, p := range pages {
		lines = append(lines, fmt.Sprintf("--- page %d ---", p.Serial), p.Header, "")
		lines = append(lines, p.Body...)
		lines = append(lines, "", p.Footer)
	}
	if len(lines) == 0 {
		return ""
	}
	return strings.Join(lines, "\n") + "\n"
}
