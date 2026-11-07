package main

type Resolution struct {
	Name, Kind, Definer              string
	Definition                       *Symbol
	Strong, Weak, Common, References []*Symbol
	Referrers                        []string
	Size, Alignment, Address         int64
	Live                             bool
}

func resolveName(name string, entries []*Symbol, script bool) *Resolution {
	r := &Resolution{Name: name, Definer: "-"}
	seen := map[*Object]bool{}
	for _, s := range entries {
		switch s.Location {
		case "undef":
			r.References = append(r.References, s)
			if !seen[s.Object] {
				r.Referrers = append(r.Referrers, s.Object.Name)
				seen[s.Object] = true
			}
		case "common":
			r.Common = append(r.Common, s)
		case "section":
			if s.Binding == "global" {
				r.Strong = append(r.Strong, s)
			} else {
				r.Weak = append(r.Weak, s)
			}
		}
	}
	switch {
	case script:
		r.Kind = "script"
		r.Definer = "*script*"
	case len(r.Strong) > 0:
		r.Kind = "global"
		r.Definition = r.Strong[0]
		r.Definer = r.Definition.Object.Name
	case len(r.Common) > 0:
		r.Kind = "common"
		for _, s := range r.Common {
			r.Size = max(r.Size, s.Size)
			r.Alignment = max(r.Alignment, s.Alignment)
		}
		for _, s := range r.Common {
			if s.Size == r.Size {
				r.Definer = s.Object.Name
				break
			}
		}
	case len(r.Weak) > 0:
		r.Kind = "weak"
		r.Definition = r.Weak[0]
		r.Definer = r.Definition.Object.Name
	default:
		r.Kind = "weakundef"
		for _, s := range r.References {
			if s.Binding == "global" {
				r.Kind = "undefined"
				break
			}
		}
	}
	return r
}
func (r *Resolution) strongDefiners(script bool) []string {
	out := []string{}
	if script {
		out = append(out, "*script*")
	}
	for _, s := range r.Strong {
		out = append(out, s.Object.Name)
	}
	return out
}
