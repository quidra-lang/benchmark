package main

import (
    "fmt"
    "os"
    "sort"
    "strconv"
    "strings"
)

type Row struct { Line int; Fields []string }
type Item struct { ID,Rule,Description string; Lead int; A,B,Safety,OnHand,Material,Labor int64 }
func readLines(name string) []string { data,err:=os.ReadFile("input/"+name); if err!=nil { panic(err) }; if len(data)==0 { return nil }; return strings.Split(strings.TrimSuffix(string(data),"\n"),"\n") }
func readRows(name string) []Row { var rows []Row; for i,line:=range readLines(name) { if i>0 { rows=append(rows,Row{i+1,strings.Split(line,",")}) } }; return rows }
func integer(text string) int64 { value,err:=strconv.ParseInt(text,10,64); if err!=nil { panic(err) }; return value }
func sortedKeys[T any](values map[string]T) []string { keys:=make([]string,0,len(values)); for key:=range values { keys=append(keys,key) }; sort.Strings(keys); return keys }
func recordError(errors *[]string,file string,line int,message string) { *errors=append(*errors,fmt.Sprintf("%s line %d: %s",file,line,message)) }
func lotValues(rule,text string) (int64,int64,bool) {
    parts:=strings.Split(text,"/"); a:=integer(parts[0]); b:=int64(0); if len(parts)==2 { b=integer(parts[1]) }
    switch rule { case "LFL": return a,b,len(parts)==1 && a==0; case "FOQ","POQ": return a,b,len(parts)==1 && a>=1; case "MIN": return a,b,len(parts)==2 && a>=1 && b>=1 }
    return a,b,false
}
func readItems(errors *[]string) map[string]*Item {
    items:=map[string]*Item{}
    for _,row:=range readRows("items.csv") {
        f:=row.Fields; reason:=""; a,b,fits:=lotValues(f[2],f[3])
        if items[f[0]]!=nil { reason="duplicate item "+f[0] } else if f[2]!="LFL" && f[2]!="FOQ" && f[2]!="POQ" && f[2]!="MIN" { reason="unknown lot rule "+f[2] } else if !fits { reason="bad lot parameter "+f[3]+" for "+f[2] }
        if reason!="" { recordError(errors,"items.csv",row.Line,reason); continue }
        items[f[0]]=&Item{ID:f[0],Lead:int(integer(f[1])),Rule:f[2],A:a,B:b,Safety:integer(f[4]),OnHand:integer(f[5]),Material:integer(f[6]),Labor:integer(f[7]),Description:f[8]}
    }
    return items
}
func (item *Item) lotLabel() string { if item.Rule=="LFL" { return "LFL" }; if item.Rule=="MIN" { return fmt.Sprintf("MIN %d/%d",item.A,item.B) }; return fmt.Sprintf("%s %d",item.Rule,item.A) }
