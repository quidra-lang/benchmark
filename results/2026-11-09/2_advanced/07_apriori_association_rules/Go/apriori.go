package main

import "sort"

type Entry struct { Set []int; Count int64 }
type Candidates struct { Joined,Excluded,Pruned int; Sets [][]int }
func generateCandidates(previous []Entry,size int,taxonomy map[int]int,exclude bool) Candidates {
 r:=Candidates{};known:=map[string]bool{};for _,e:=range previous {known[setKey(e.Set)]=true}
 for i,a:=range previous {for _,b:=range previous[i+1:] {
  if compareSets(a.Set[:size-2],b.Set[:size-2])!=0 {break};set:=append(append([]int(nil),a.Set...),b.Set[len(b.Set)-1]);r.Joined++
  if exclude&&size==2 {first,ok:=taxonomy[set[0]];second,other:=taxonomy[set[1]];if ok&&first==set[1]||other&&second==set[0] {r.Excluded++;continue}}
  pruned:=false;for j:=range set {part:=append(append([]int(nil),set[:j]...),set[j+1:]...);if !known[setKey(part)] {pruned=true;break}};if pruned {r.Pruned++} else {r.Sets=append(r.Sets,set)}
 }}
 sort.Slice(r.Sets,func(i,j int)bool{return compareSets(r.Sets[i],r.Sets[j])<0});return r
}
func countCandidates(support *Support,sets [][]int,minimum int64) []Entry {var entries []Entry;for _,set:=range sets {count:=support.count(set);if count>=minimum {entries=append(entries,Entry{set,count})}};return entries}
