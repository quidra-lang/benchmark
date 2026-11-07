package main

import (
    "fmt"
    "os"
    "strings"
)

func money(cents int64) string { return fmt.Sprintf("%d.%02d",cents/100,cents%100) }
func percentage(part,whole int64) int64 { return (200*part+whole)/(2*whole) }
func tableRow(label string,values []int64,width int) string { var line strings.Builder; fmt.Fprintf(&line,"%-10s",label); for _,value:=range values { fmt.Fprintf(&line,"%*d",width,value) }; return line.String() }
func writeReport(name string,lines []string) { text:=""; if len(lines)>0 { text=strings.Join(lines,"\n")+"\n" }; if err:=os.WriteFile("output/"+name,[]byte(text),0644);err!=nil { panic(err) } }
