package main

import (
	"fmt"
	"os"
	"sort"
	"strings"
)

func format(x float64, k int) string {
	s := fmt.Sprintf("%.*f", k, x)
	if strings.HasPrefix(s, "-") && strings.Trim(s[1:], "0.") == "" {
		return s[1:]
	}
	return s
}
func symbol(mask, n int) string {
	b := make([]byte, n)
	for i := range b {
		b[i] = '.'
		if mask>>i&1 != 0 {
			b[i] = '*'
		}
	}
	return string(b)
}
func sortedMasks(set map[int]bool, n int) []int {
	var a []int
	for mask := range set {
		a = append(a, mask)
	}
	sort.Slice(a,
		func(i, j int) bool { return symbol(a[i], n) < symbol(a[j], n) })
	return a
}
func newick(t Tree, taxa []Record, outgroup int, lengths bool, support map[int]int) string {
	r := rootTree(t,
		taxa, outgroup)
	var visit func(int) string
	visit = func(v int) string {
		s := ""
		if v < len(taxa) {
			s = taxa[v].Name
		} else {
			var parts []string
			for _, c := range r.Children[v] {
				parts = append(parts, visit(c))
			}
			s = "(" + strings.Join(parts, ",") + ")"
			if v != r.Root && support != nil {
				s += fmt.Sprint(support[r.Masks[v]])
			}
		}
		if v != r.Root && lengths {
			s += ":" + format(t.Adj[v][r.Parent[v]],
				5)
		}
		return s
	}
	return visit(r.Root) + ";"
}
func cladogram(s *strings.Builder, t Tree, taxa []Record, outgroup int, support map[int]int) {
	r := rootTree(t,
		taxa, outgroup)
	line(s, "*")
	var visit func(int, string, bool)
	visit = func(v int, prefix string, last bool) {
		connector := "|-- "
		if last {
			connector = "`-- "
		}
		label := ""
		if v < len(taxa) {
			label = taxa[v].Name
		} else {
			label = fmt.Sprintf("[%d]",
				support[r.Masks[v]])
		}
		line(s, "%s%s%s", prefix, connector, label)
		next := prefix + "|   "
		if last {
			next = prefix + "    "
		}
		for i, c := range r.Children[v] {
			visit(c, next, i == len(r.Children[v])-1)
		}
	}
	for i, c := range r.Children[r.Root] {
		visit(c,
			"", i == len(r.Children[r.Root])-1)
	}
}
func line(s *strings.Builder, template string, a ...any) { fmt.Fprintf(s, template+"\n", a...) }
func write(path string, s *strings.Builder)              { must(os.WriteFile(path, []byte(s.String()), 0644)) }
