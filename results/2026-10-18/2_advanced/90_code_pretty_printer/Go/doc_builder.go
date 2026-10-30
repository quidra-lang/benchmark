package main

type Doc struct {
	Kind, Text, Other, Mode string
	Number                  int
	Children                []*Doc
	Forced                  bool
}

func text(s string) *Doc      { return &Doc{Kind: "text", Text: s} }
func marker(kind string) *Doc { return &Doc{Kind: kind} }
func cat(docs ...*Doc) *Doc {
	out := []*Doc{}
	var add func(*Doc)
	add = func(d *Doc) {
		if d == nil {
			return
		}
		if d.Kind == "concat" {
			for _, child := range d.Children {
				add(child)
			}
			return
		}
		if d.Kind == "text" {
			if d.Text == "" {
				return
			}
			if len(out) > 0 && out[len(out)-1].Kind == "text" {
				out[len(out)-1] = text(out[len(out)-1].Text + d.Text)
				return
			}
		}
		out = append(out, d)
	}
	for _, d := range docs {
		add(d)
	}
	if len(out) == 0 {
		return text("")
	}
	if len(out) == 1 {
		return out[0]
	}
	return &Doc{Kind: "concat", Children: out}
}
func forceBroken(d *Doc) bool {
	if d.Kind == "hardline" || d.Kind == "break_parent" {
		return true
	}
	for _, child := range d.Children {
		if forceBroken(child) {
			return true
		}
	}
	return false
}
func group(docs ...*Doc) *Doc {
	child := cat(docs...)
	return &Doc{Kind: "group", Children: []*Doc{child}, Forced: forceBroken(child)}
}
func nest(n int, docs ...*Doc) *Doc {
	return &Doc{Kind: "nest", Number: n, Children: []*Doc{cat(docs...)}}
}
func align(docs ...*Doc) *Doc  { return &Doc{Kind: "align", Children: []*Doc{cat(docs...)}} }
func suffix(s string) *Doc     { return &Doc{Kind: "suffix", Text: s} }
func ifBreak(a, b string) *Doc { return &Doc{Kind: "if_break", Text: a, Other: b} }
func groupMetrics(d *Doc) (int, int, int) {
	groups, broken, forced := 0, 0, 0
	if d.Kind == "group" {
		groups++
		if d.Mode == "break" || d.Mode == "forced" {
			broken++
		}
		if d.Mode == "forced" {
			forced++
		}
	}
	for _, child := range d.Children {
		g, b, f := groupMetrics(child)
		groups += g
		broken += b
		forced += f
	}
	return groups, broken, forced
}
