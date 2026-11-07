package main

import "math"

type Center struct { Value, Fraction float64 }
type LotPoint struct { Value, LCL, UCL, Z float64; Status string }
func attributeCenter(chart int,chosen []int,lots []Lot) Center {
 var d,c,n int64
 for _,i:=range chosen {l:=lots[i-1]; d+=int64(l.Defectives);c+=int64(l.Defects);n+=int64(l.Inspected)}
 fraction:=float64(d)/float64(n); value:=fraction
 switch chart {case 1:value=float64(d)/float64(len(chosen));case 2:value=float64(c)/float64(len(chosen));case 3:value=float64(c)/float64(n)}
 return Center{value,fraction}
}
func attributePoint(chart int,l Lot,c Center) LotPoint {
 v,sigma:=0.0,0.0
 switch chart {
 case 0:v=float64(l.Defectives)/float64(l.Inspected);sigma=math.Sqrt(c.Value*(1-c.Value)/float64(l.Inspected))
 case 1:v=float64(l.Defectives);sigma=math.Sqrt(c.Value*(1-c.Fraction))
 case 2:v=float64(l.Defects);sigma=math.Sqrt(c.Value)
 case 3:v=float64(l.Defects)/float64(l.Inspected);sigma=math.Sqrt(c.Value/float64(l.Inspected))
 }
 p:=LotPoint{v,math.Max(0,c.Value-3*sigma),c.Value+3*sigma,(v-c.Value)/sigma,"ok"}
 if v>p.UCL {p.Status="high"} else if v<p.LCL {p.Status="low"}; return p
}
