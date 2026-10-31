package main

import (
 "math"
 "sort"
)

type Neighbor struct { Row *Row; Distance float64 }
type Prediction struct { Label,Runner string; Share,RunnerShare,Estimate float64; Neighbors []Neighbor }
func distance(a,b []float64,metric string) float64 {total,dot,aa,bb:=0.0,0.0,0.0,0.0;for j,x:=range a {y:=b[j];d:=x-y;switch metric {case "squared_euclidean":total+=d*d;case "manhattan":total+=math.Abs(d);case "chebyshev":total=math.Max(total,math.Abs(d));case "cosine":dot+=x*y;aa+=x*x;bb+=y*y}};if metric=="cosine" {na,nb:=math.Sqrt(aa),math.Sqrt(bb);if na==0||nb==0 {return 1};return 1-dot/(na*nb)};return total}
func sortNeighbors(order []Neighbor) {sort.Slice(order,func(i,j int)bool{if order[i].Distance!=order[j].Distance {return order[i].Distance<order[j].Distance};return order[i].Row.ID<order[j].Row.ID})}
func neighborOrder(query []float64,rows []*Row,vectors [][]float64,metric string) []Neighbor {order:=make([]Neighbor,len(rows));for j,r:=range rows {order[j]=Neighbor{r,distance(query,vectors[j],metric)}};sortNeighbors(order);return order}
func prediction(order []Neighbor,k int,weighting string) Prediction {
 nearest:=order[:min(k,len(order))];type Tally struct {Label string;Count int;Distance,Weight float64};tallies:=map[string]*Tally{};weightTotal,targets,weighted:=0.0,0.0,0.0
 for _,n:=range nearest {w:=1/(n.Distance+0.000000001);t:=tallies[n.Row.Label];if t==nil {t=&Tally{Label:n.Row.Label};tallies[t.Label]=t};t.Count++;t.Distance+=n.Distance;t.Weight+=w;weightTotal+=w;targets+=n.Row.Target;weighted+=w*n.Row.Target};var ranked []*Tally;for _,t:=range tallies {ranked=append(ranked,t)};sort.Slice(ranked,func(i,j int)bool{a,b:=ranked[i],ranked[j];if weighting=="uniform" {if a.Count!=b.Count {return a.Count>b.Count}} else if a.Weight!=b.Weight {return a.Weight>b.Weight};if a.Distance!=b.Distance {return a.Distance<b.Distance};return a.Label<b.Label});share:=func(t *Tally)float64{if weighting=="uniform" {return float64(t.Count)/float64(len(nearest))};return t.Weight/weightTotal};p:=Prediction{Label:ranked[0].Label,Share:share(ranked[0]),Neighbors:nearest};if len(ranked)>1 {p.Runner=ranked[1].Label;p.RunnerShare=share(ranked[1])};if weighting=="uniform" {p.Estimate=targets/float64(len(nearest))} else {p.Estimate=weighted/weightTotal};return p
}
