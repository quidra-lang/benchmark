package main

import (
 "os"
 "sort"
 "strconv"
 "strings"
)

type Row struct { ID,Label string; Values []float64; Target float64; HasTarget bool; Index int }
type Settings struct { Scalings,Metrics,Weightings []string; K,Curve []int; Folds,EditK,Top int; Bins []float64 }
type Dataset struct { Features,Labels []string; Train,Test []*Row; Settings Settings }
func readLines(name string) []string {data,e:=os.ReadFile("input/"+name);if e!=nil {panic(e)};return strings.Split(strings.TrimSuffix(string(data),"\n"),"\n")}
func decimal(s string) float64 {v,e:=strconv.ParseFloat(s,64);if e!=nil {panic(e)};return v}
func integer(s string) int {v,e:=strconv.Atoi(s);if e!=nil {panic(e)};return v}
func readRows(name string,offset int) ([]string,[]*Row) {lines:=readLines(name);header:=strings.Split(lines[0],",");var rows []*Row;for _,line:=range lines[1:] {p:=strings.Split(line,",");r:=&Row{ID:p[0],Label:p[len(p)-2],Index:offset+len(rows)};for _,v:=range p[1:len(p)-2] {r.Values=append(r.Values,decimal(v))};if p[len(p)-1]!="" {r.Target=decimal(p[len(p)-1]);r.HasTarget=true};rows=append(rows,r)};return header[1:len(header)-2],rows}
func readDataset() Dataset {features,train:=readRows("train.csv",0);_,test:=readRows("test.csv",len(train));s:=Settings{};for _,line:=range readLines("params.txt") {p:=strings.Fields(line);switch p[0] {case "SCALINGS":s.Scalings=p[1:];case "METRICS":s.Metrics=p[1:];case "WEIGHTINGS":s.Weightings=p[1:];case "K_VALUES":for _,v:=range p[1:] {s.K=append(s.K,integer(v))};case "CURVE":for _,v:=range p[1:] {s.Curve=append(s.Curve,integer(v))};case "BINS":for _,v:=range p[1:] {s.Bins=append(s.Bins,decimal(v))};case "FOLDS":s.Folds=integer(p[1]);case "EDIT_K":s.EditK=integer(p[1]);case "TOP":s.Top=integer(p[1])}}
 labels:=map[string]bool{};for _,r:=range train {labels[r.Label]=true};var ordered []string;for label:=range labels {ordered=append(ordered,label)};sort.Strings(ordered);return Dataset{features,ordered,train,test,s}}
