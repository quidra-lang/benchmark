package main

import (
 "os"
 "strconv"
 "strings"
)

type Settings struct {
 Name string
 LSL, USL, Target, Size, Phase1, Passes, Span, Gap, Bin, Window, Step int
 K, H, Lambda, E, Z float64
 Rules [7][]int
}
type Constants struct { A2, A3, B3, B4, D3, D4, D2, C4 float64 }
type Lot struct { Number, Inspected, Defectives, Defects int }
var chartNames = []string{"XBAR_R", "R", "XBAR_S", "S", "I", "MR", "CUSUM", "EWMA", "MA"}
var familyNames = []string{"XBAR_R", "XBAR_S", "I_MR"}
var attributeNames = []string{"p", "np", "c", "u"}
var constants = []Constants{
 {1.880,2.659,0,3.267,0,3.267,1.128,0.7979},
 {1.023,1.954,0,2.568,0,2.574,1.693,0.8862},
 {0.729,1.628,0,2.266,0,2.282,2.059,0.9213},
 {0.577,1.427,0,2.089,0,2.114,2.326,0.9400},
 {0.483,1.287,0.030,1.970,0,2.004,2.534,0.9515},
 {0.419,1.182,0.118,1.882,0.076,1.924,2.704,0.9594},
 {0.373,1.099,0.185,1.815,0.136,1.864,2.847,0.9650},
 {0.337,1.032,0.239,1.761,0.184,1.816,2.970,0.9693},
 {0.308,0.975,0.284,1.716,0.223,1.777,3.078,0.9727},
}
func inputLines(name string) []string { b,e:=os.ReadFile("input/"+name); if e!=nil { panic(e) }; return strings.Split(strings.TrimSuffix(string(b),"\n"),"\n") }
func integer(s string) int { n,e:=strconv.Atoi(s); if e!=nil {panic(e)}; return n }
func decimal(s string) float64 { n,e:=strconv.ParseFloat(s,64); if e!=nil {panic(e)}; return n }
func readDataset() (Settings,[]int,[]Lot) {
 s:=Settings{}
 for _,line:=range inputLines("spec.txt") {
  p:=strings.Fields(line)
  if p[0]=="rules" { ix:=6; for j:=0;j<6;j++ {if p[1]==chartNames[j] {ix=j}}; for _,v:=range p[2:] {s.Rules[ix]=append(s.Rules[ix],integer(v))}; continue }
  switch p[0] {
  case "characteristic":s.Name=p[1]
  case "lsl":s.LSL=integer(p[1])
  case "usl":s.USL=integer(p[1])
  case "target":s.Target=integer(p[1])
  case "subgroup_size":s.Size=integer(p[1])
  case "phase1_subgroups":s.Phase1=integer(p[1])
  case "max_passes":s.Passes=integer(p[1])
  case "cusum_k":s.K=decimal(p[1])
  case "cusum_h":s.H=decimal(p[1])
  case "ewma_lambda":s.Lambda=decimal(p[1])
  case "ewma_l":s.E=decimal(p[1])
  case "ma_span":s.Span=integer(p[1])
  case "event_gap":s.Gap=integer(p[1])
  case "ci_z":s.Z=decimal(p[1])
  case "histogram_bin":s.Bin=integer(p[1])
  case "rolling_window":s.Window=integer(p[1])
  case "rolling_step":s.Step=integer(p[1])
  }
 }
 var values []int; for _,line:=range inputLines("measurements.csv")[1:] {p:=strings.Split(line,","); values=append(values,integer(p[2]))}
 var lots []Lot; for _,line:=range inputLines("attributes.csv")[1:] {p:=strings.Split(line,","); lots=append(lots,Lot{integer(p[0]),integer(p[1]),integer(p[2]),integer(p[3])})}
 return s,values,lots
}
