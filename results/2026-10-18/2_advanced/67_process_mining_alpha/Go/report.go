package main

import (
	"fmt"
	"os"
	"sort"
	"strings"
)

type Ratio struct{ N, D int64 }

func newRatio(n, d int64) Ratio {
	a, b := n, d
	if a < 0 {
		a = -a
	}
	for b != 0 {
		a, b = b, a%b
	}
	return Ratio{n / a, d / a}
}
func ratio(n, d int) Ratio { return newRatio(int64(n), int64(d)) }
func (r Ratio) compare(s Ratio) int {
	a, b := r.N*s.D, s.N*r.D
	if a < b {
		return -1
	}
	if a > b {
		return 1
	}
	return 0
}
func (r Ratio) subtract(s Ratio) Ratio { return newRatio(r.N*s.D-s.N*r.D, r.D*s.D) }
func (r Ratio) String() string {
	n := r.N
	sign := ""
	if n < 0 {
		n = -n
		sign = "-"
	}
	t := 10000 * n / r.D
	ds := sign
	if t == 0 {
		ds = ""
	}
	return fmt.Sprintf("%s%d/%d=%s%d.%04d",
		sign, n, r.D, ds, t/10000, t%10000)
}
func parseRatio(s string) Ratio {
	a := strings.Split(s, "/")
	return ratio(integer(a[0]), integer(a[1]))
}
func percent(a, b int) string {
	t := 10000 * int64(a) / int64(b)
	return fmt.Sprintf("%d.%02d%%", t/100, t%100)
}
func list(a []string) string {
	if len(a) == 0 {
		return "-"
	}
	return strings.Join(a, ",")
}
func line(s *strings.Builder, template string, a ...any) { fmt.Fprintf(s, template+"\n", a...) }
func write(path string, s *strings.Builder)              { must(os.WriteFile(path, []byte(s.String()), 0644)) }
func sortNames(a []string)                               { sort.Strings(a) }
func sortInts(a []int)                                   { sort.Ints(a) }
func names(set map[string]bool) []string {
	a := make([]string, 0, len(set))
	for s := range set {
		a = append(a, s)
	}
	sort.Strings(a)
	return a
}
func yes(b bool) string {
	if b {
		return "yes"
	}
	return "no"
}
