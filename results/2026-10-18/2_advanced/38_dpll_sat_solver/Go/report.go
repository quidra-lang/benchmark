package main

import (
	"fmt"
	"os"
	"sort"
	"strings"
)

type NamedValue struct {
	Name  string
	Value any
}

func named(items ...NamedValue) string {
	parts := make([]string, len(items))
	for i, item := range items {
		parts[i] = fmt.Sprintf("%s=%v", item.Name, item.Value)
	}
	return strings.Join(parts, " ")
}
func numberList(values []int) string {
	if len(values) == 0 {
		return "-"
	}
	parts := make([]string, len(values))
	for i, v := range values {
		parts[i] = fmt.Sprint(v)
	}
	return strings.Join(parts, ",")
}
func frequency(values []int) string {
	counts := map[int]int{}
	for _, v := range values {
		counts[v]++
	}
	keys := []int{}
	for k := range counts {
		keys = append(keys, k)
	}
	sort.Ints(keys)
	parts := []string{}
	for _, k := range keys {
		parts = append(parts, fmt.Sprintf("%d:%d", k, counts[k]))
	}
	if len(parts) == 0 {
		return "-"
	}
	return strings.Join(parts, ",")
}
func heading(j *Job) string { return fmt.Sprintf("JOB %d %s", j.Number, j.Text) }
func saveLines(name string, lines []string) {
	text := ""
	if len(lines) > 0 {
		text = strings.Join(lines, "\n") + "\n"
	}
	if err := os.WriteFile("output/"+name, []byte(text), 0644); err != nil {
		panic(err)
	}
}
func saveParagraphs(name string, paragraphs [][]string) {
	parts := []string{}
	for _, lines := range paragraphs {
		parts = append(parts, strings.Join(lines, "\n"))
	}
	text := strings.Join(parts, "\n\n")
	if text != "" {
		text += "\n"
	}
	if err := os.WriteFile("output/"+name, []byte(text), 0644); err != nil {
		panic(err)
	}
}
func queensBoard(columns []int) []string {
	lines := []string{}
	for _, c := range columns {
		lines = append(lines, strings.Repeat(".", c-1)+"Q"+strings.Repeat(".", len(columns)-c))
	}
	return lines
}
