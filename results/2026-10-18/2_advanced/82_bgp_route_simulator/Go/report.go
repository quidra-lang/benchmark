package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

func pathText(a []int) string {
	out := make([]string, len(a))
	for i, n := range a {
		out[i] = strconv.Itoa(n)
	}
	return strings.Join(out, ",")
}
func attributeText(a *Attribute) string {
	return fmt.Sprintf("path %s origin %s med %d comm %s", pathText(a.Path), a.Origin, a.MED, communitiesText(a.Communities))
}
func routeText(r *Route) string {
	if r == nil {
		return "NONE"
	}
	a := r.Attribute
	if r.Local {
		return fmt.Sprintf("LOCAL origin %s comm %s", a.Origin, communitiesText(a.Communities))
	}
	return fmt.Sprintf("next %d path %s link %s lp %d med %d origin %s comm %s", a.Path[0], pathText(a.Path), r.Link.Name, r.LP, a.MED, a.Origin, communitiesText(a.Communities))
}
func writeLines(name string, a []string) {
	s := ""
	if len(a) > 0 {
		s = strings.Join(a, "\n") + "\n"
	}
	if e := os.WriteFile("output/"+name, []byte(s), 0644); e != nil {
		panic(e)
	}
}
