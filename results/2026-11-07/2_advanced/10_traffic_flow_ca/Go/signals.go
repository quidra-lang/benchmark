package main

import "fmt"

type Phase struct { duration int; token string; greens map[string]bool }
type Junction struct { node string; offset, cycle int; phases []Phase }
func (j *Junction) Green(id string, t int) bool { if len(j.phases) == 0 { return true }; tau := (t-1+j.offset)%j.cycle; for _, p := range j.phases { if tau < p.duration { return p.greens[id] }; tau -= p.duration }; return false }
func (j *Junction) Lines() []string {
 if len(j.phases) == 0 { return []string{"JUNCTION "+j.node+" unsignalized"} }; lines := []string{fmt.Sprintf("JUNCTION %s signal cycle %d offset %d",j.node,j.cycle,j.offset)}; start := 0
 for k, p := range j.phases { lines = append(lines,fmt.Sprintf("  PHASE %d %d-%d %s",k+1,start,start+p.duration-1,p.token)); start += p.duration }; return lines
}
