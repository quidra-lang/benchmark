package main

import "math"

type Scaling struct { Centers,Scales []float64 }
func computeScaling(rows []*Row,method string) Scaling {d:=len(rows[0].Values);s:=Scaling{make([]float64,d),make([]float64,d)};for j:=0;j<d;j++ {if method=="standard" {total:=0.0;for _,r:=range rows {total+=r.Values[j]};center:=total/float64(len(rows));s.Centers[j]=center;if len(rows)>1 {squares:=0.0;for _,r:=range rows {v:=r.Values[j]-center;squares+=v*v};s.Scales[j]=math.Sqrt(squares/float64(len(rows)-1))}} else {low,high:=rows[0].Values[j],rows[0].Values[j];for _,r:=range rows {low=math.Min(low,r.Values[j]);high=math.Max(high,r.Values[j])};s.Centers[j]=low;s.Scales[j]=high-low}};return s}
func (s Scaling) transform(row *Row,features []int) []float64 {v:=make([]float64,len(features));for j,i:=range features {if s.Scales[i]>0 {v[j]=(row.Values[i]-s.Centers[i])/s.Scales[i]}};return v}
