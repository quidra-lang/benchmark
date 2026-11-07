package main

import "math"

type Subgroup struct { Values []int; Total, Squares, Range int64; Mean, SD float64 }
type Limits struct { LCL, CL, UCL float64 }
type Series struct { Numbers []int; Values []float64 }
func (l Limits) outside(v float64) bool {return v<l.LCL || v>l.UCL}
func subgroupStatistics(values []int,n int) []Subgroup {
 var result []Subgroup
 for start:=0;start<len(values);start+=n {
  g:=Subgroup{Values:values[start:start+n]}; low,high:=values[start],values[start]
  for _,v:=range g.Values {g.Total+=int64(v); g.Squares+=int64(v)*int64(v); low=min(low,v); high=max(high,v)}
  g.Range=int64(high-low); g.Mean=float64(g.Total)/float64(n); g.SD=math.Sqrt(float64(int64(n)*g.Squares-g.Total*g.Total)/float64(n*(n-1))); result=append(result,g)
 }
 return result
}
func familyLimits(family int,numbers []int,groups []Subgroup,values []int,n int,c Constants) [2]Limits {
 var sum,spread int64; sd:=0.0
 if family==2 {
  for j,t:=range numbers {sum+=int64(values[t-1]); if j>0 {spread+=int64(abs(values[t-1]-values[numbers[j-1]-1]))}}
  mean,r:=float64(sum)/float64(len(numbers)),float64(spread)/float64(len(numbers)-1)
  return [2]Limits{{mean-3*r/constants[0].D2,mean,mean+3*r/constants[0].D2},{constants[0].D3*r,r,constants[0].D4*r}}
 }
 for _,i:=range numbers {g:=groups[i-1]; sum+=g.Total; spread+=g.Range; sd+=g.SD}
 mean:=float64(sum)/float64(len(numbers)*n)
 if family==0 {r:=float64(spread)/float64(len(numbers)); return [2]Limits{{mean-c.A2*r,mean,mean+c.A2*r},{c.D3*r,r,c.D4*r}}}
 sd/=float64(len(numbers)); return [2]Limits{{mean-c.A3*sd,mean,mean+c.A3*sd},{c.B3*sd,sd,c.B4*sd}}
}
func familySeries(family int,numbers []int,groups []Subgroup,values []int) [2]Series {
 var result [2]Series
 for j,t:=range numbers {
  result[0].Numbers=append(result[0].Numbers,t)
  if family==2 {result[0].Values=append(result[0].Values,float64(values[t-1])); if j>0 {result[1].Numbers=append(result[1].Numbers,t); result[1].Values=append(result[1].Values,float64(abs(values[t-1]-values[numbers[j-1]-1])))}} else {
   g:=groups[t-1]; result[0].Values=append(result[0].Values,g.Mean); result[1].Numbers=append(result[1].Numbers,t); v:=g.SD; if family==0 {v=float64(g.Range)}; result[1].Values=append(result[1].Values,v)
  }
 }
 return result
}
func abs(v int) int {if v<0 {return -v};return v}
