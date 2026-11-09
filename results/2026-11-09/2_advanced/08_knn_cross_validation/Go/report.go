package main

import (
 "fmt"
 "math"
 "os"
 "strconv"
 "strings"
)

func fixed(v float64,places int) string {text:=strconv.FormatFloat(v,'f',places,64);if strings.HasPrefix(text,"-") {rounded,_:=strconv.ParseFloat(text,64);if rounded==0 {return text[1:]}};return text}
func real(v float64) string {return fixed(v,4)}
func four(v float64) float64 {return math.Round(v*10000)}
func ratio(a,b int) string {return fmt.Sprintf("%d/%d %s",a,b,real(float64(a)/float64(b)))}
func fraction(a,b int) string {if b==0 {return "- -"};x,y:=a,b;for y!=0 {x,y=y,x%y};return fmt.Sprintf("%d/%d %s",a/x,b/x,real(float64(a)/float64(b)))}
func writeReport(name string,lines []string) {if e:=os.MkdirAll("output",0755);e!=nil {panic(e)};if e:=os.WriteFile("output/"+name,[]byte(strings.Join(lines,"\n")+"\n"),0644);e!=nil {panic(e)}}
