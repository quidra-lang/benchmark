package main

import (
    "fmt"
    "os"
    "sort"
    "strings"
)

const ( MPS=iota; CustomerOrder; Dependent; Safety )
const ( Stock=iota; Receipt; Planned )
type ScheduleRow struct { Item string; Week int; Quantity int64; Line int }
type Inquiry struct { ID,Item string; Quantity int64; Week,Line int }
type Demand struct { Item string; Kind,Week int; Quantity int64; OrderID string; Line int; Parent string; ParentNumber int }
type PlannedOrder struct { Item string; Number,Receipt,Original,Release int; Quantity int64 }
type Allocation struct { Demand *Demand; Share int64 }
type Supply struct { Kind,Week,Line int; Quantity,Remaining int64; Order *PlannedOrder; Allocations []Allocation; Roots []*Demand }
type ItemPlan struct { Demands []*Demand; Gross,OnHand,Net,PR,PL [27]int64; Orders []*PlannedOrder; PastDue int64; Supplies,OrderSupplies []*Supply }
type Plan struct { Items map[string]*ItemPlan; Loads,Overloads map[string]*[27]int64 }
type Promise struct { Inquiry *Inquiry; Week,Material int; Reason string }
type PlanningData struct {
    Horizon int
    Peg []string
    TreeQuantity int64
    Errors []string
    Items map[string]*Item
    BOM *BOM
    Centers map[string]*WorkCenter
    Routings map[string][]Operation
    MPS,Receipts []ScheduleRow
    Inquiries []*Inquiry
    Codes,Cumulative map[string]int
    Order,ItemOrder,CenterOrder []string
    Scheduled map[string]*[27]int64
    ItemReceipts map[string][]ScheduleRow
    Weeks []int64
}
func (data *PlanningData) scheduleError(id string,week int,quantity int64) string {
    if data.Items[id]==nil { return "unknown item "+id }; if week<1 || week>data.Horizon { return fmt.Sprintf("week %d outside horizon",week) }; if quantity<1 { return fmt.Sprintf("bad quantity %d",quantity) }; return ""
}
func (data *PlanningData) readSchedule(name string,unique bool) []ScheduleRow {
    var result []ScheduleRow; seen:=map[string]bool{}
    for _,row:=range readRows(name) { f:=row.Fields; week,quantity:=int(integer(f[1])),integer(f[2]); reason:=data.scheduleError(f[0],week,quantity); key:=fmt.Sprintf("%s %d",f[0],week); if reason=="" && unique && seen[key] { reason=fmt.Sprintf("duplicate %s week %d",f[0],week) }; if reason!="" { recordError(&data.Errors,name,row.Line,reason) } else { result=append(result,ScheduleRow{f[0],week,quantity,row.Line}); seen[key]=true } }
    return result
}
func loadData() *PlanningData {
    data:=&PlanningData{}
    for _,line:=range readLines("params.txt") { words:=strings.Split(line," "); switch words[0] { case "horizon": data.Horizon=int(integer(words[1])); case "peg": data.Peg=words[1:]; case "tree_quantity": data.TreeQuantity=integer(words[1]) } }
    data.Items=readItems(&data.Errors); data.BOM=readBOM(data.Items,&data.Errors); data.Centers=readCenters(&data.Errors); data.Routings=readRoutings(data.Items,data.Centers,data.BOM,&data.Errors)
    data.MPS=data.readSchedule("mps.csv",true); data.Receipts=data.readSchedule("receipts.csv",false); seen:=map[string]bool{}
    for _,row:=range readRows("orders.csv") { f:=row.Fields; quantity,week:=integer(f[2]),int(integer(f[3])); reason:=""; if seen[f[0]] { reason="duplicate order "+f[0] } else { reason=data.scheduleError(f[1],week,quantity) }; if reason!="" { recordError(&data.Errors,"orders.csv",row.Line,reason) } else { data.Inquiries=append(data.Inquiries,&Inquiry{f[0],f[1],quantity,week,row.Line}); seen[f[0]]=true } }
    data.Codes,data.Cumulative,data.Order=data.BOM.structure(data.Items); data.ItemOrder=sortedKeys(data.Items); data.CenterOrder=sortedKeys(data.Centers)
    data.Scheduled=map[string]*[27]int64{}; data.ItemReceipts=map[string][]ScheduleRow{}
    for id:=range data.Items { data.Scheduled[id]=&[27]int64{} }; for week:=1;week<=data.Horizon;week++ { data.Weeks=append(data.Weeks,int64(week)) }
    sort.Slice(data.Receipts,func(i,j int)bool { a,b:=data.Receipts[i],data.Receipts[j]; if a.Week!=b.Week { return a.Week<b.Week }; return a.Line<b.Line })
    for _,row:=range data.Receipts { data.ItemReceipts[row.Item]=append(data.ItemReceipts[row.Item],row); data.Scheduled[row.Item][row.Week]+=row.Quantity }; return data
}
func (data *PlanningData) runMRP(promised []*Demand,extra *Demand) *Plan {
    plan:=&Plan{Items:map[string]*ItemPlan{},Loads:map[string]*[27]int64{},Overloads:map[string]*[27]int64{}}
    for id:=range data.Items { plan.Items[id]=&ItemPlan{} }
    for _,row:=range data.MPS { plan.Items[row.Item].Demands=append(plan.Items[row.Item].Demands,&Demand{Item:row.Item,Kind:MPS,Week:row.Week,Quantity:row.Quantity,Line:row.Line}) }
    for _,demand:=range promised { plan.Items[demand.Item].Demands=append(plan.Items[demand.Item].Demands,demand) }; if extra!=nil { plan.Items[extra.Item].Demands=append(plan.Items[extra.Item].Demands,extra) }
    for _,id:=range data.Order {
        p,item:=plan.Items[id],data.Items[id]
        for _,demand:=range p.Demands { p.Gross[demand.Week]+=demand.Quantity }; projected:=item.OnHand
        for week:=1;week<=data.Horizon;week++ {
            available:=projected+data.Scheduled[id][week]-p.Gross[week]; projected=available
            if available<item.Safety { quantity:=lotSize(item,week,available,data.Scheduled[id],&p.Gross,data.Horizon); original:=week-item.Lead; order:=&PlannedOrder{id,len(p.Orders)+1,week,original,max(1,original),quantity}; p.Orders=append(p.Orders,order); p.Net[week]=item.Safety-available; p.PR[week]=quantity; p.PL[order.Release]+=quantity; projected=available+quantity; if original<1 { p.PastDue+=quantity } }; p.OnHand[week]=projected
        }
        for _,order:=range p.Orders { for _,link:=range data.BOM.Children[id] { plan.Items[link.Child].Demands=append(plan.Items[link.Child].Demands,&Demand{Item:link.Child,Kind:Dependent,Week:order.Release,Quantity:need(link,order.Quantity),Parent:id,ParentNumber:order.Number}) } }
    }
    for _,id:=range data.CenterOrder { plan.Loads[id]=&[27]int64{}; plan.Overloads[id]=&[27]int64{} }
    for _,id:=range data.Order { operations:=data.Routings[id]; for _,order:=range plan.Items[id].Orders { for index,operation:=range operations { week:=operationWeek(order.Receipt,data.Items[id].Lead,index,len(operations)); plan.Loads[operation.Center][week]+=operation.Setup+order.Quantity*operation.Run } } }
    for _,id:=range data.CenterOrder { for week:=1;week<=data.Horizon;week++ { plan.Overloads[id][week]=max(int64(0),plan.Loads[id][week]-data.Centers[id].Available) } }; return plan
}
func (data *PlanningData) promise(base *Plan) ([]Promise,*Plan) {
    current:=base; var promised []*Demand; var promises []Promise
    for _,inquiry:=range data.Inquiries {
        promise:=Promise{Inquiry:inquiry}
        for week:=inquiry.Week;week<=data.Horizon;week++ {
            demand:=&Demand{Item:inquiry.Item,Kind:CustomerOrder,Week:week,Quantity:inquiry.Quantity,OrderID:inquiry.ID,Line:inquiry.Line}; trial:=data.runMRP(promised,demand); reason:=""
            for _,id:=range data.Order { if trial.Items[id].PastDue>current.Items[id].PastDue { reason=id; break } }
            if reason=="" { if promise.Material==0 { promise.Material=week }; for _,id:=range data.CenterOrder { for w:=1;w<=data.Horizon;w++ { if trial.Overloads[id][w]>current.Overloads[id][w] { reason=fmt.Sprintf("%s week %d",id,w); break } }; if reason!="" { break } } }
            if reason=="" { promise.Week=week; promised=append(promised,demand); current=trial; break }; if week==inquiry.Week { promise.Reason=reason }
        }
        promises=append(promises,promise)
    }
    return promises,current
}
func (d *Demand) text() string { switch d.Kind { case Safety: return "SAFETY "+d.Item; case MPS: return fmt.Sprintf("MPS %s week %d",d.Item,d.Week); case CustomerOrder: return fmt.Sprintf("ORDER %s %s week %d",d.OrderID,d.Item,d.Week) }; return fmt.Sprintf("%s order %d week %d",d.Parent,d.ParentNumber,d.Week) }
func demandLess(a,b *Demand) bool { if a.Week!=b.Week { return a.Week<b.Week }; if a.Kind!=b.Kind { return a.Kind<b.Kind }; if a.Kind==CustomerOrder { return a.Line<b.Line }; if a.Kind==Dependent { if a.Parent!=b.Parent { return a.Parent<b.Parent }; return a.ParentNumber<b.ParentNumber }; return false }
func rootLess(a,b *Demand) bool { if a.Item!=b.Item { return a.Item<b.Item }; if a.Kind!=b.Kind { return a.Kind<b.Kind }; if a.Week!=b.Week { return a.Week<b.Week }; return a.OrderID<b.OrderID }
func rootKey(d *Demand) string { return fmt.Sprintf("%s|%d|%d|%s",d.Item,d.Kind,d.Week,d.OrderID) }
func parentSupply(plan *Plan,demand *Demand) *Supply { return plan.Items[demand.Parent].OrderSupplies[demand.ParentNumber-1] }
func (data *PlanningData) peg(plan *Plan) {
    for _,id:=range data.Order {
        p,item:=plan.Items[id],data.Items[id]
        if item.OnHand>0 { p.Supplies=append(p.Supplies,&Supply{Kind:Stock,Quantity:item.OnHand,Remaining:item.OnHand}) }
        for _,row:=range data.ItemReceipts[id] { p.Supplies=append(p.Supplies,&Supply{Kind:Receipt,Week:row.Week,Line:row.Line,Quantity:row.Quantity,Remaining:row.Quantity}) }
        for _,order:=range p.Orders { supply:=&Supply{Kind:Planned,Week:order.Receipt,Quantity:order.Quantity,Remaining:order.Quantity,Order:order}; p.Supplies=append(p.Supplies,supply); p.OrderSupplies=append(p.OrderSupplies,supply) }
        sort.Slice(p.Supplies,func(i,j int)bool { a,b:=p.Supplies[i],p.Supplies[j]; if a.Week!=b.Week { return a.Week<b.Week }; if a.Kind!=b.Kind { return a.Kind<b.Kind }; return a.Line<b.Line })
        demands:=append([]*Demand(nil),p.Demands...); sort.SliceStable(demands,func(i,j int)bool { return demandLess(demands[i],demands[j]) }); if item.Safety>0 { demands=append([]*Demand{{Item:id,Kind:Safety,Quantity:item.Safety}},demands...) }
        index:=0
        for _,demand:=range demands { remaining:=demand.Quantity; for remaining>0 { for p.Supplies[index].Remaining==0 { index++ }; supply:=p.Supplies[index]; share:=min(remaining,supply.Remaining); supply.Allocations=append(supply.Allocations,Allocation{demand,share}); supply.Remaining-=share; remaining-=share } }
        for _,supply:=range p.OrderSupplies { roots:=map[string]*Demand{}; for _,allocation:=range supply.Allocations { demand:=allocation.Demand; if demand.Kind==Dependent { for _,root:=range parentSupply(plan,demand).Roots { roots[rootKey(root)]=root } } else { roots[rootKey(demand)]=demand } }; for _,root:=range roots { supply.Roots=append(supply.Roots,root) }; sort.Slice(supply.Roots,func(i,j int)bool { return rootLess(supply.Roots[i],supply.Roots[j]) }) }
    }
}
func sum(values []int64) int64 { total:=int64(0); for _,value:=range values { total+=value }; return total }
func depthLabel(depth int) string { return strings.Repeat(".",depth)+fmt.Sprint(depth) }
func (data *PlanningData) gridLines(plan *Plan) []string {
    var lines []string
    for _,id:=range data.Order { p,item:=plan.Items[id],data.Items[id]; lines=append(lines,fmt.Sprintf("ITEM %s LLC %d LT %d LOT %s SS %d OH %d %s",id,data.Codes[id],item.Lead,item.lotLabel(),item.Safety,item.OnHand,item.Description)); for _,row:=range []struct{label string; values []int64}{{"WEEK",data.Weeks},{"GROSS",p.Gross[1:data.Horizon+1]},{"RECEIPTS",data.Scheduled[id][1:data.Horizon+1]},{"ON_HAND",p.OnHand[1:data.Horizon+1]},{"NET",p.Net[1:data.Horizon+1]},{"PLAN_RCPT",p.PR[1:data.Horizon+1]},{"PLAN_REL",p.PL[1:data.Horizon+1]}} { lines=append(lines,tableRow(row.label,row.values,6)) }; lines=append(lines,fmt.Sprintf("TOTAL gross %d receipts %d planned %d orders %d ending %d",sum(p.Gross[:]),sum(data.Scheduled[id][:]),sum(p.PR[:]),len(p.Orders),p.OnHand[data.Horizon])) }
    return lines
}
func (data *PlanningData) peggingLines(plan *Plan) []string {
    var lines []string
    var whereUsed func(string,int,int64)
    whereUsed=func(id string,depth int,extension int64) { for _,link:=range data.BOM.Parents[id] { ext:=extension*link.Quantity; lines=append(lines,fmt.Sprintf("%s %s qty %d ext %d",depthLabel(depth),link.Parent,link.Quantity,ext)); whereUsed(link.Parent,depth+1,ext) } }
    var allocations func(*Supply,int)
    allocations=func(supply *Supply,depth int) { for _,allocation:=range supply.Allocations { lines=append(lines,fmt.Sprintf("%sALLOC %d %s",strings.Repeat(" ",2*depth),allocation.Share,allocation.Demand.text())); if supply.Kind==Planned && allocation.Demand.Kind==Dependent { allocations(parentSupply(plan,allocation.Demand),depth+1) } } }
    for _,id:=range data.Peg { p:=plan.Items[id]; lines=append(lines,fmt.Sprintf("PEG %s orders %d",id,len(p.Orders))); whereUsed(id,1,1); for kind:=Stock;kind<=Planned;kind++ { for _,supply:=range p.Supplies { if supply.Kind!=kind { continue }; switch kind { case Stock: lines=append(lines,fmt.Sprintf("STOCK quantity %d",supply.Quantity)); case Receipt: lines=append(lines,fmt.Sprintf("RECEIPT line %d week %d quantity %d",supply.Line,supply.Week,supply.Quantity)); case Planned: order:=supply.Order; lines=append(lines,fmt.Sprintf("ORDER %d receipt %d release %d quantity %d",order.Number,order.Receipt,order.Release,order.Quantity)) }; allocations(supply,1); if supply.Remaining>0 { lines=append(lines,fmt.Sprintf("  EXCESS %d",supply.Remaining)) }; for _,root:=range supply.Roots { lines=append(lines,"  ROOT "+root.text()) } } } }; return lines
}
func (data *PlanningData) treeLines() []string {
    var lines []string
    var explode func(string,int64,int64,int,map[string]int64)
    explode=func(id string,gross,extension int64,depth int,totals map[string]int64) { for _,link:=range data.BOM.Children[id] { child:=data.Items[link.Child]; ext,quantity:=extension*link.Quantity,need(link,gross); totals[link.Child]+=quantity; lines=append(lines,fmt.Sprintf("%s %s qty %d scrap %d ext %d gross %d lt %d cum %d %s",depthLabel(depth),link.Child,link.Quantity,link.Scrap,ext,quantity,child.Lead,data.Cumulative[link.Child],child.Description)); explode(link.Child,quantity,ext,depth+1,totals) } }
    for _,id:=range data.ItemOrder { if len(data.BOM.Children[id])==0 || len(data.BOM.Parents[id])>0 { continue }; item:=data.Items[id]; lines=append(lines,fmt.Sprintf("TREE %s quantity %d",id,data.TreeQuantity),fmt.Sprintf("0 %s ext 1 gross %d lt %d cum %d %s",id,data.TreeQuantity,item.Lead,data.Cumulative[id],item.Description)); totals:=map[string]int64{}; explode(id,data.TreeQuantity,1,1,totals); for _,child:=range sortedKeys(totals) { lines=append(lines,fmt.Sprintf("SUM %s %d",child,totals[child])) }; path:=[]string{id}; current:=id; for len(data.BOM.Children[current])>0 { chosen:=data.BOM.Children[current][0].Child; for _,link:=range data.BOM.Children[current] { if data.Cumulative[link.Child]>data.Cumulative[chosen] { chosen=link.Child } }; path=append(path,chosen); current=chosen }; lines=append(lines,fmt.Sprintf("CRITICAL %s cum %d",strings.Join(path," -> "),data.Cumulative[id])) }; return lines
}

func (data *PlanningData) costLines(plan *Plan,costs map[string]StandardCost) []string {
    usages,values:=map[string]int64{},map[string]int64{}; for id:=range data.Items { usages[id]=sum(plan.Items[id].Gross[:]); values[id]=usages[id]*costs[id].Total }; classes:=abcClasses(values)
    lines:=[]string{"item,material,labor,total,usage,value,class"}; for _,id:=range data.ItemOrder { cost:=costs[id]; lines=append(lines,fmt.Sprintf("%s,%s,%s,%s,%d,%s,%s",id,money(cost.Material),money(cost.Labor),money(cost.Total),usages[id],money(values[id]),classes[id])) }; return lines
}
func (data *PlanningData) exceptionLines(plan *Plan) []string {
    lines:=make([]string,0,len(data.Errors)); for _,error:=range data.Errors { lines=append(lines,"ERROR "+error) }
    kinds:=[]string{"BELOW_SAFETY","PAST_DUE","RELEASE","EXPEDITE","DEFER","CANCEL","NO_ROUTING","NO_DEMAND","OVERLOAD"}; counts:=map[string]int{}
    message:=func(text string) { lines=append(lines,text); kind,_,_:=strings.Cut(text," "); counts[kind]++ }
    for _,id:=range data.Order {
        p,item:=plan.Items[id],data.Items[id]
        if item.OnHand<item.Safety { message(fmt.Sprintf("BELOW_SAFETY %s on hand %d safety %d",id,item.OnHand,item.Safety)) }
        for _,order:=range p.Orders { if order.Original<1 { message(fmt.Sprintf("PAST_DUE %s order %d receipt %d release %d late %d quantity %d",id,order.Number,order.Receipt,order.Original,1-order.Original,order.Quantity)) } else if order.Original==1 { message(fmt.Sprintf("RELEASE %s order %d receipt %d quantity %d",id,order.Number,order.Receipt,order.Quantity)) } }
        var balances [27]int64; balance:=item.OnHand; for week:=1;week<=data.Horizon;week++ { balance-=p.Gross[week]; balances[week]=balance }; covered:=int64(0)
        for _,receipt:=range data.ItemReceipts[id] { needWeek:=0; for week:=1;week<=data.Horizon;week++ { if balances[week]+covered<item.Safety { needWeek=week; break } }; text:=fmt.Sprintf("%s receipt line %d week %d quantity %d",id,receipt.Line,receipt.Week,receipt.Quantity); if needWeek==0 { message("CANCEL "+text) } else if needWeek<receipt.Week { message(fmt.Sprintf("EXPEDITE %s to %d",text,needWeek)) } else if needWeek>receipt.Week { message(fmt.Sprintf("DEFER %s to %d",text,needWeek)) }; covered+=receipt.Quantity }
        if len(data.BOM.Children[id])>0 && len(data.Routings[id])==0 { message("NO_ROUTING "+id) }; if sum(p.Gross[:])==0 && item.OnHand>0 { message(fmt.Sprintf("NO_DEMAND %s on hand %d",id,item.OnHand)) }
    }
    for _,id:=range data.CenterOrder { for week:=1;week<=data.Horizon;week++ { if plan.Overloads[id][week]>0 { message(fmt.Sprintf("OVERLOAD %s week %d load %d available %d",id,week,plan.Loads[id][week],data.Centers[id].Available)) } } }
    summary:=fmt.Sprintf("SUMMARY errors %d",len(data.Errors)); for _,kind:=range kinds { summary+=fmt.Sprintf(" %s %d",strings.ToLower(kind),counts[kind]) }; return append(lines,summary)
}
func (data *PlanningData) capacityLines(plan *Plan) []string {
    var lines []string; totals:=map[string]int64{}
    for _,id:=range data.CenterOrder {
        center:=data.Centers[id]; loads,overloads:=plan.Loads[id],plan.Overloads[id]; leveled:=levelLoads(loads,center.Available,data.Horizon); total:=sum(loads[:]); totals[id]=total; var utilization [27]int64; peak,overloaded:=0,0
        for week:=1;week<=data.Horizon;week++ { utilization[week]=percentage(loads[week],center.Available); if overloads[week]>0 { overloaded++ }; if total>0 && (peak==0 || loads[week]>loads[peak]) { peak=week } }
        lines=append(lines,fmt.Sprintf("CENTER %s minutes %d efficiency %d available %d %s",id,center.Minutes,center.Efficiency,center.Available,center.Description))
        for _,row:=range []struct{label string; values []int64}{{"WEEK",data.Weeks},{"LOAD",loads[1:data.Horizon+1]},{"UTIL",utilization[1:data.Horizon+1]},{"OVER",overloads[1:data.Horizon+1]},{"LEVELED",leveled[1:data.Horizon+1]}} { lines=append(lines,tableRow(row.label,row.values,7)) }
        lines=append(lines,fmt.Sprintf("TOTAL load %d available %d utilization %d overloaded %d peak %d backlog %d",total,center.Available*int64(data.Horizon),percentage(total,center.Available*int64(data.Horizon)),overloaded,peak,max(int64(0),leveled[1]-center.Available)))
    }
    order:=append([]string(nil),data.CenterOrder...); sort.Slice(order,func(i,j int)bool { a,b:=order[i],order[j]; left,right:=totals[a]*data.Centers[b].Available,totals[b]*data.Centers[a].Available; if left!=right { return left>right }; return a<b })
    for rank,id:=range order { lines=append(lines,fmt.Sprintf("RANK %d %s load %d utilization %d",rank+1,id,totals[id],percentage(totals[id],data.Centers[id].Available*int64(data.Horizon)))) }; return lines
}
func (data *PlanningData) promiseLines(promises []Promise,base,final *Plan) []string {
    var lines []string; onTime,late,rejected:=0,0,0
    for _,promise:=range promises {
        inquiry:=promise.Inquiry; head:=fmt.Sprintf("ORDER %s %s quantity %d requested %d",inquiry.ID,inquiry.Item,inquiry.Quantity,inquiry.Week); material:="none"; if promise.Material>0 { material=fmt.Sprint(promise.Material) }
        if promise.Week==0 { rejected++; lines=append(lines,fmt.Sprintf("%s rejected material %s reason %s",head,material,promise.Reason)); continue }
        if promise.Week==inquiry.Week { onTime++; lines=append(lines,fmt.Sprintf("%s promised %d",head,promise.Week)) } else { late++; lines=append(lines,fmt.Sprintf("%s promised %d late %d material %s reason %s",head,promise.Week,promise.Week-inquiry.Week,material,promise.Reason)) }
        for _,id:=range data.Order { for _,supply:=range final.Items[id].OrderSupplies { serves:=false; for _,root:=range supply.Roots { if root.Kind==CustomerOrder && root.OrderID==inquiry.ID { serves=true; break } }; if serves { order:=supply.Order; lines=append(lines,fmt.Sprintf("  SUPPLY %s order %d receipt %d release %d quantity %d",id,order.Number,order.Receipt,order.Release,order.Quantity)) } } }
    }
    for _,id:=range data.Order { before,after:=base.Items[id],final.Items[id]; for week:=1;week<=data.Horizon;week++ { if before.PR[week]!=after.PR[week] { lines=append(lines,fmt.Sprintf("CHANGE %s from %d planned %d -> %d orders %d -> %d",id,week,sum(before.PR[:]),sum(after.PR[:]),len(before.Orders),len(after.Orders))); break } } }
    return append(lines,fmt.Sprintf("SUMMARY orders %d on_time %d late %d rejected %d",len(promises),onTime,late,rejected))
}
func (data *PlanningData) releaseLines(plan *Plan) []string {
    var orders []*PlannedOrder; available:=map[string]int64{}
    for _,id:=range data.Order { available[id]=data.Items[id].OnHand+data.Scheduled[id][1]; for _,order:=range plan.Items[id].Orders { if order.Release==1 { orders=append(orders,order) } } }
    sort.Slice(orders,func(i,j int)bool { a,b:=orders[i],orders[j]; if a.Original!=b.Original { return a.Original<b.Original }; if a.Item!=b.Item { return a.Item<b.Item }; return a.Number<b.Number })
    var lines []string; made,readyCount,bought:=0,0,0; purchaseTotal:=int64(0)
    for _,order:=range orders {
        item:=data.Items[order.Item]; lateness:=""; if order.Original<1 { lateness=fmt.Sprintf(" late %d",1-order.Original) }; head:=fmt.Sprintf("%s order %d receipt %d quantity %d%s",order.Item,order.Number,order.Receipt,order.Quantity,lateness)
        if len(data.BOM.Children[order.Item])==0 { value:=order.Quantity*item.Material; bought++; purchaseTotal+=value; lines=append(lines,"BUY "+head+" value "+money(value)); continue }
        ready:=true; var detail []string; needs:=make([]int64,len(data.BOM.Children[order.Item]))
        for i,link:=range data.BOM.Children[order.Item] { quantity:=need(link,order.Quantity); needs[i]=quantity; if quantity>available[link.Child] { ready=false }; detail=append(detail,fmt.Sprintf("  PICK %s need %d available %d short %d",link.Child,quantity,available[link.Child],max(int64(0),quantity-available[link.Child]))) }
        if ready { readyCount++; for i,link:=range data.BOM.Children[order.Item] { available[link.Child]-=needs[i] } }; operations:=data.Routings[order.Item]
        for i,operation:=range operations { detail=append(detail,fmt.Sprintf("  OPERATION %d %s week %d minutes %d",operation.Number,operation.Center,operationWeek(order.Receipt,item.Lead,i,len(operations)),operation.Setup+order.Quantity*operation.Run)) }
        made++; status:="SHORT"; if ready { status="READY" }; lines=append(lines,"MAKE "+head+" "+status); lines=append(lines,detail...)
    }
    return append(lines,fmt.Sprintf("SUMMARY make %d ready %d short %d buy %d value %s",made,readyCount,made-readyCount,bought,money(purchaseTotal)))
}
func (data *PlanningData) valueLines(plan *Plan,costs map[string]StandardCost) []string {
    lines:=[]string{"week,inventory,purchases,labor"}
    for week:=1;week<=data.Horizon;week++ { inventory,purchases,labor:=int64(0),int64(0),int64(0); for _,id:=range data.Order { p,item:=plan.Items[id],data.Items[id]; inventory+=p.OnHand[week]*costs[id].Total; if len(data.BOM.Children[id])>0 { labor+=p.PL[week]*item.Labor } else { purchases+=p.PL[week]*item.Material } }; lines=append(lines,fmt.Sprintf("%d,%s,%s,%s",week,money(inventory),money(purchases),money(labor))) }; return lines
}
func main() {
    data:=loadData(); base:=data.runMRP(nil,nil); promises,final:=data.promise(base); data.peg(final); costs:=standardCosts(data.Items,data.BOM,data.Order)
    if err:=os.MkdirAll("output",0755);err!=nil { panic(err) }
    writeReport("mrp_grid.txt",data.gridLines(final)); writeReport("pegging.txt",data.peggingLines(final)); writeReport("bom_tree.txt",data.treeLines()); writeReport("cost_rollup.csv",data.costLines(final,costs)); writeReport("exceptions.txt",data.exceptionLines(final)); writeReport("capacity.txt",data.capacityLines(final)); writeReport("promises.txt",data.promiseLines(promises,base,final)); writeReport("releases.txt",data.releaseLines(final)); writeReport("value_plan.csv",data.valueLines(final,costs))
}
