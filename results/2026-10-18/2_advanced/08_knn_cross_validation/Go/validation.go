package main

import (
 "fmt"
 "math"
 "sort"
)

type Model struct { K int; Metric,Weighting,Scaling string }
func (m Model) notation() string {return fmt.Sprintf("k=%d metric=%s weighting=%s scaling=%s",m.K,m.Metric,m.Weighting,m.Scaling)}
func stratified(rows []*Row,count int) [][]int {order:=make([]int,len(rows));for j:=range order {order[j]=j};sort.Slice(order,func(i,j int)bool{a,b:=rows[order[i]],rows[order[j]];if a.Label!=b.Label {return a.Label<b.Label};return a.ID<b.ID});folds:=make([][]int,count);for position,j:=range order {folds[position%count]=append(folds[position%count],j)};for _,fold:=range folds {sort.Ints(fold)};return folds}
func trainingRows(rows []*Row,excluded []int) []*Row {skip:=make([]bool,len(rows));for _,j:=range excluded {skip[j]=true};var out []*Row;for j,r:=range rows {if !skip[j] {out=append(out,r)}};return out}
func neighborOrders(train,queries []*Row,scaling,metric string,features []int) [][]Neighbor {s:=computeScaling(train,scaling);vectors:=make([][]float64,len(train));for j,r:=range train {vectors[j]=s.transform(r,features)};orders:=make([][]Neighbor,len(queries));for j,r:=range queries {orders[j]=neighborOrder(s.transform(r,features),train,vectors,metric)};return orders}
func predictRows(m Model,train,queries []*Row,features []int) []Prediction {orders:=neighborOrders(train,queries,m.Scaling,m.Metric,features);out:=make([]Prediction,len(queries));for j,order:=range orders {out[j]=prediction(order,m.K,m.Weighting)};return out}
func rmse(errors []float64) float64 {sum:=0.0;for _,v:=range errors {sum+=v*v};return math.Sqrt(sum/float64(len(errors)))}
func mae(errors []float64) float64 {sum:=0.0;for _,v:=range errors {sum+=math.Abs(v)};return sum/float64(len(errors))}
func rSquared(errors,targets []float64) float64 {sum:=0.0;for _,v:=range targets {sum+=v};mean:=sum/float64(len(targets));residual,spread:=0.0,0.0;for _,v:=range errors {residual+=v*v};for _,v:=range targets {d:=v-mean;spread+=d*d};return 1-residual/spread}
