package main

import (
    "fmt"
    "sort"
)

type WorkCenter struct { ID,Description string; Minutes,Efficiency,Available int64 }
type Operation struct { Number int; Center string; Setup,Run int64 }
func readCenters(errors *[]string) map[string]*WorkCenter {
    centers:=map[string]*WorkCenter{}
    for _,row:=range readRows("workcenters.csv") { f:=row.Fields; efficiency:=integer(f[2]); reason:=""; if centers[f[0]]!=nil { reason="duplicate center "+f[0] } else if efficiency<50 || efficiency>150 { reason=fmt.Sprintf("bad efficiency %d",efficiency) }; if reason!="" { recordError(errors,"workcenters.csv",row.Line,reason) } else { minutes:=integer(f[1]); centers[f[0]]=&WorkCenter{f[0],f[3],minutes,efficiency,minutes*efficiency/100} } }
    return centers
}
func readRoutings(items map[string]*Item,centers map[string]*WorkCenter,bom *BOM,errors *[]string) map[string][]Operation {
    routings:=map[string][]Operation{}
    for _,row:=range readRows("routings.csv") {
        f:=row.Fields; number,run:=int(integer(f[1])),integer(f[4]); reason:=""
        switch { case items[f[0]]==nil: reason="unknown item "+f[0]; case centers[f[2]]==nil: reason="unknown center "+f[2]; case len(bom.Children[f[0]])==0: reason="purchased item "+f[0]; case run<1: reason=fmt.Sprintf("bad run time %d",run) }
        if reason=="" { for _,operation:=range routings[f[0]] { if operation.Number==number { reason=fmt.Sprintf("duplicate %s operation %d",f[0],number); break } } }
        if reason!="" { recordError(errors,"routings.csv",row.Line,reason) } else { routings[f[0]]=append(routings[f[0]],Operation{number,f[2],integer(f[3]),run}) }
    }
    for id:=range routings { sort.Slice(routings[id],func(i,j int)bool { return routings[id][i].Number<routings[id][j].Number }) }; return routings
}
func operationWeek(receipt,lead,index,count int) int { return max(receipt-lead+index*lead/count,1) }
func levelLoads(loads *[27]int64,available int64,horizon int) [27]int64 { var leveled [27]int64; carry:=int64(0); for week:=horizon;week>=2;week-- { total:=loads[week]+carry; leveled[week]=min(total,available); carry=total-leveled[week] }; leveled[1]=loads[1]+carry; return leveled }
