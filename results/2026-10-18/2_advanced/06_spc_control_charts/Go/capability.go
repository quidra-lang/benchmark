package main

import (
 "fmt"
 "math"
 "strings"
)

type Capability struct {
 Count,Below,Above int
 Mean,Within,Sbar,Overall,CP,CPU,CPL,CPK,PP,PPU,PPL,PPK,CPM,PPM float64
 CPKCI,PPKCI [2]float64
 Values []int
 Verdict string
}
func capability(chosen []int,groups []Subgroup,s Settings,c Constants) Capability {
 r:=Capability{};var total,ranges int64;sd:=0.0
 for _,i:=range chosen {g:=groups[i-1];r.Values=append(r.Values,g.Values...);total+=g.Total;ranges+=g.Range;sd+=g.SD}
 r.Count=len(r.Values);r.Mean=float64(total)/float64(r.Count);r.Within=(float64(ranges)/float64(len(chosen)))/c.D2;r.Sbar=(sd/float64(len(chosen)))/c.C4
 squares:=0.0;for _,v:=range r.Values {d:=float64(v)-r.Mean;squares+=d*d;if v<s.LSL {r.Below++};if v>s.USL {r.Above++}}
 r.Overall=math.Sqrt(squares/float64(r.Count-1));r.CP,r.CPU,r.CPL,r.CPK=indices(r.Mean,r.Within,s);r.PP,r.PPU,r.PPL,r.PPK=indices(r.Mean,r.Overall,s)
 d:=r.Mean-float64(s.Target);r.CPM=float64(s.USL-s.LSL)/(6*math.Sqrt(r.Overall*r.Overall+d*d));r.CPKCI=interval(r.CPK,r.Count,s.Z);r.PPKCI=interval(r.PPK,r.Count,s.Z);r.PPM=float64(1000000*(r.Below+r.Above))/float64(r.Count)
 r.Verdict="incapable";if r.CPK>=1.33 {r.Verdict="capable"} else if r.CPK>=1 {r.Verdict="marginal"};return r
}
func indices(mean,sigma float64,s Settings) (float64,float64,float64,float64) {p:=float64(s.USL-s.LSL)/(6*sigma);u:=(float64(s.USL)-mean)/(3*sigma);l:=(mean-float64(s.LSL))/(3*sigma);return p,u,l,math.Min(u,l)}
func interval(x float64,n int,z float64) [2]float64 {d:=z*math.Sqrt(1/float64(9*n)+x*x/float64(2*(n-1)));return [2]float64{x-d,x+d}}
func histogram(values []int,s Settings) []string {
 low,high:=s.LSL,s.USL;for _,v:=range values {low=min(low,v);high=max(high,v)};low=s.Bin*(low/s.Bin);high=s.Bin*(high/s.Bin)+s.Bin
 counts:=make([]int,(high-low)/s.Bin);top:=0;for _,v:=range values {i:=(v-low)/s.Bin;counts[i]++;top=max(top,counts[i])}
 var lines []string
 for j,count:=range counts {a:=low+j*s.Bin;b:=a+s.Bin-1;line:=fmt.Sprintf("bin %d %d %d",a,b,count);if count>0 {line+=" "+strings.Repeat("#",(50*count+top-1)/top)};for k,p:=range []int{s.LSL,s.Target,s.USL} {if a<=p&&p<=b {line+=" "+[]string{"lsl","target","usl"}[k]}};lines=append(lines,line)}
 return lines
}
