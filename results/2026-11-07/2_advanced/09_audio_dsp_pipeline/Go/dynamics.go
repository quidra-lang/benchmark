package main

func envelope(x []int64,attack,release int64) []int64 {env:=make([]int64,len(x));var e int64;for n,v:=range x {a:=min(absolute(v),int64(32767));c:=release;if a>e {c=attack};e+=rdiv((a-e)*c,32768);env[n]=e};return env}
func normalize(x []int64,target int64) ([]int64,int64) {p:=peak(x);y:=append([]int64(nil),x...);if p>0 {for n,v:=range x {y[n]=rdiv(v*target,p)}};return y,p}
func gate(x []int64,threshold,hold int64) ([]int64,int64) {y:=make([]int64,len(x));last:=-int64(len(x))-hold-1;var muted int64;for n,v:=range x {if absolute(v)>=threshold {last=int64(n)};if int64(n)-last<=hold {y[n]=v} else {muted++}};return y,muted}
func compress(x []int64,threshold,ratioNum,ratioDen,attack,release int64) ([]int64,int64,int64) {env:=envelope(x,attack,release);y:=make([]int64,len(x));g,minimum:=int64(32768),int64(32768);var reduced int64;for n,v:=range x {e:=env[n];target:=int64(32768);if e>threshold {d:=threshold+rdiv((e-threshold)*ratioDen,ratioNum);target=rdiv(d*32768,e)};if target<g {g=target} else {g+=rdiv((target-g)*release,32768)};minimum=min(minimum,g);if g<32768 {reduced++};y[n]=rdiv(v*g,32768)};return y,minimum,reduced}
