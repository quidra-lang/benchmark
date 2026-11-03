package main

type Zones struct { Limits; U1,U2,L1,L2 float64 }
type Signal struct { Chart,Rule,Start,End int; Value float64; Direction string }
func zones(l Limits) Zones {a,b:=(l.UCL-l.CL)/3,(l.CL-l.LCL)/3;return Zones{l,l.CL+a,l.CL+2*a,l.CL-b,l.CL-2*b}}
func zoneName(l Limits,v float64) string {z:=zones(l);switch {case v>z.UCL:return "OUT+";case v<z.LCL:return "OUT-";case v>z.U2:return "A+";case v>z.U1:return "B+";case v>z.CL:return "C+";case v<z.L2:return "A-";case v<z.L1:return "B-";case v<z.CL:return "C-"};return "C0"}
func checkRules(chart int,s Series,l Limits,rules []int) []Signal {
 lengths:=[9]int{0,1,3,5,8,6,14,15,8}; z:=zones(l); var signals []Signal
 for k:=1;k<=len(s.Values);k++ {for _,r:=range rules {
  w:=lengths[r];if k<w {continue};v:=s.Values[k-1]; window:=s.Values[k-w:k];direction:=""
  switch r {
  case 1:if l.outside(v) {direction="DOWN";if v>l.CL {direction="UP"}}
  case 2,3:u,d,needed:=z.U2,z.L2,2;if r==3 {u,d,needed=z.U1,z.L1,4};up,down:=0,0;for _,x:=range window {if x>u {up++};if x<d {down++}};if v>u && up>=needed {direction="UP"} else if v<d && down>=needed {direction="DOWN"}
  case 4:up,down:=true,true;for _,x:=range window {up=up&&x>z.CL;down=down&&x<z.CL};if up {direction="UP"} else if down {direction="DOWN"}
  case 5:up,down:=true,true;for j:=1;j<w;j++ {up=up&&window[j]>window[j-1];down=down&&window[j]<window[j-1]};if up {direction="UP"} else if down {direction="DOWN"}
  case 6:ok:=true;previous:=0.0;for j:=1;j<w;j++ {d:=window[j]-window[j-1];if d==0 || j>1&&(d>0)==(previous>0) {ok=false};previous=d};if ok {direction="NONE"}
  case 7:ok:=true;for _,x:=range window {ok=ok&&z.L1<x&&x<z.U1};if ok {direction="NONE"}
  case 8:ok,up,down:=true,false,false;for _,x:=range window {ok=ok&&(x>z.U1||x<z.L1);up=up||x>z.U1;down=down||x<z.L1};if ok&&up&&down {direction="NONE"}
  }
  if direction!="" {signals=append(signals,Signal{chart,r,s.Numbers[k-w],s.Numbers[k-1],v,direction})}
 }}
 return signals
}
