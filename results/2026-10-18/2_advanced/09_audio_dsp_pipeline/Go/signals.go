package main

import (
 "fmt"
 "os"
 "strconv"
 "strings"
)

type Signal struct { Name string; Rate int64; Samples []int64; Origin string; Ingredients []*Signal }
func floorDiv(a,b int64) int64 {q,r:=a/b,a%b;if r!=0&&(r>0)!=(b>0) {q--};return q}
func rdiv(a,b int64) int64 {return floorDiv(2*a+b,2*b)}
func absolute(v int64) int64 {if v<0 {return -v};return v}
func saturation(v int64,clips *int64) int64 {if v< -32768 {if clips!=nil {(*clips)++};return -32768};if v>32767 {if clips!=nil {(*clips)++};return 32767};return v}
func peak(values []int64) int64 {var p int64;for _,v:=range values {p=max(p,absolute(v))};return p}
func sampleSum(values []int64) int64 {var total int64;for _,v:=range values {total+=v};return total}
func integer(s string) int64 {v,e:=strconv.ParseInt(s,10,64);if e!=nil {panic(e)};return v}
func readSignals() []*Signal {data,e:=os.ReadFile("input/signals.txt");if e!=nil {panic(e)};tokens:=strings.Fields(string(data));var signals []*Signal;for index:=0;index<len(tokens); {name,rate,length:=tokens[index+1],integer(tokens[index+2]),int(integer(tokens[index+3]));s:=&Signal{Name:name,Rate:rate,Origin:"input",Samples:make([]int64,length)};for j:=range s.Samples {s.Samples[j]=integer(tokens[index+4+j])};signals=append(signals,s);index+=4+length};return signals}
func signalLines(s *Signal) []string {lines:=[]string{fmt.Sprintf("SIGNAL %s %d %d",s.Name,s.Rate,len(s.Samples))};for first:=0;first<len(s.Samples);first+=16 {var parts []string;for _,v:=range s.Samples[first:min(first+16,len(s.Samples))] {parts=append(parts,strconv.FormatInt(v,10))};lines=append(lines,strings.Join(parts," "))};return lines}
func testSignal(command string,rate,count,pos,amp,seed int64) []int64 {values:=make([]int64,int(count));switch command {case "IMPULSE":values[int(pos)]=amp;case "STEP":for j:=int(pos);j<len(values);j++ {values[j]=amp};case "NOISE":state:=seed;for j:=range values {state=(48271*state)%2147483647;values[j]=state%65536-32768}};return values}
