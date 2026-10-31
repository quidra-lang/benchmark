package main

import (
 "os"
 "sort"
 "strconv"
 "strings"
)

type Product struct { Name,Category string; Price int64 }
type Basket struct { ID,Customer string; Day int; Counts map[int]int64 }
func readLines(name string) []string {data,e:=os.ReadFile("input/"+name);if e!=nil {panic(e)};return strings.Split(strings.TrimSuffix(string(data),"\n"),"\n")}
func records(name string) [][]string {var rows [][]string;for _,line:=range readLines(name)[1:] {rows=append(rows,strings.Split(line,","))};return rows}
func parseInt(s string) int64 {v,e:=strconv.ParseInt(s,10,64);if e!=nil {panic(e)};return v}
func (b *Basket) items(taxonomy map[int]int,extended bool) []int {found:=map[int]bool{};for i:=range b.Counts {found[i]=true;if extended {found[taxonomy[i]]=true}};var ids []int;for i:=range found {ids=append(ids,i)};sort.Ints(ids);return ids}
func contains(items []bool,set []int) bool {for _,i:=range set {if !items[i] {return false}};return true}
func itemSets(baskets []*Basket,taxonomy map[int]int,extended bool,width int) [][]bool {sets:=make([][]bool,len(baskets));for j,b:=range baskets {set:=make([]bool,width);for _,i:=range b.items(taxonomy,extended) {set[i]=true};sets[j]=set};return sets}
func setKey(set []int) string {parts:=make([]string,len(set));for j,i:=range set {parts[j]=strconv.Itoa(i)};return strings.Join(parts,",")}
func compareSets(a,b []int) int {for j:=0;j<min(len(a),len(b));j++ {if a[j]<b[j] {return -1};if a[j]>b[j] {return 1}};if len(a)<len(b) {return -1};if len(a)>len(b) {return 1};return 0}
func subset(a,b []int) bool {j:=0;for _,i:=range b {if j<len(a)&&a[j]==i {j++}};return j==len(a)}
func union(a,b []int) []int {all:=append(append([]int(nil),a...),b...);sort.Ints(all);var out []int;for _,i:=range all {if len(out)==0||out[len(out)-1]!=i {out=append(out,i)}};return out}
func selected(set []int,mask int) []int {var out []int;for j,i:=range set {if mask&(1<<j)!=0 {out=append(out,i)}};return out}
type Support struct { Sets [][]bool; Cache map[string]int64 }
func newSupport(sets [][]bool) *Support {return &Support{sets,map[string]int64{"":int64(len(sets))}}}
func (s *Support) count(set []int) int64 {key:=setKey(set);if count,ok:=s.Cache[key];ok {return count};var count int64;for _,b:=range s.Sets {if contains(b,set) {count++}};s.Cache[key]=count;return count}
