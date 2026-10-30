package main

import "slices"

type Attribute struct {
	Path        []int
	Origin      string
	MED         int
	Communities []uint64
}
type Route struct {
	Attribute *Attribute
	Local     bool
	LP        int
	Link      *Link
}

func sameAttribute(a, b *Attribute) bool {
	if a == nil || b == nil {
		return a == nil && b == nil
	}
	return a.Origin == b.Origin && a.MED == b.MED && slices.Equal(a.Path, b.Path) && slices.Equal(a.Communities, b.Communities)
}
func sameRoute(a, b *Route) bool {
	if a == nil || b == nil {
		return a == nil && b == nil
	}
	return a.Local == b.Local && a.LP == b.LP && a.Link == b.Link && sameAttribute(a.Attribute, b.Attribute)
}
func originRank(s string) int {
	if s == "IGP" {
		return 0
	}
	if s == "EGP" {
		return 1
	}
	return 2
}
func bestRoute(input []*Route, t *Topology) (*Route, string) {
	a := slices.Clone(input)
	if len(a) == 1 {
		return a[0], "ONLY"
	}
	for _, stage := range []string{"LOCALPREF", "ASPATH", "ORIGIN", "MED", "ROUTERID", "LINK"} {
		keep := []*Route{}
		if stage == "MED" {
			minimum := map[int]int{}
			for _, r := range a {
				n := r.Attribute.Path[0]
				old, ok := minimum[n]
				if !ok || r.Attribute.MED < old {
					minimum[n] = r.Attribute.MED
				}
			}
			for _, r := range a {
				if r.Attribute.MED == minimum[r.Attribute.Path[0]] {
					keep = append(keep, r)
				}
			}
		} else {
			value := func(r *Route) int64 {
				switch stage {
				case "LOCALPREF":
					return -int64(r.LP)
				case "ASPATH":
					return int64(len(r.Attribute.Path))
				case "ORIGIN":
					return int64(originRank(r.Attribute.Origin))
				case "ROUTERID":
					return int64(t.ByNumber[r.Attribute.Path[0]].Router)
				default:
					return int64(r.Link.Number)
				}
			}
			minimum := value(a[0])
			for _, r := range a {
				minimum = min(minimum, value(r))
			}
			for _, r := range a {
				if value(r) == minimum {
					keep = append(keep, r)
				}
			}
		}
		a = keep
		if len(a) == 1 {
			return a[0], stage
		}
	}
	return a[0], "LINK"
}
