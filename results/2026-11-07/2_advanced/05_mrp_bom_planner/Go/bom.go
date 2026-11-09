package main

import (
    "fmt"
    "sort"
    "strings"
)

type Link struct { Parent,Child string; Quantity,Scrap int64 }
type BOM struct { Children,Parents map[string][]Link }
func need(link Link,quantity int64) int64 { return (quantity*link.Quantity*(100+link.Scrap)+99)/100 }
func (bom *BOM) path(id,target string,visited map[string]bool) []string {
    if id==target { return []string{id} }; visited[id]=true
    for _,link:=range bom.Children[id] { if !visited[link.Child] { if rest:=bom.path(link.Child,target,visited);rest!=nil { return append([]string{id},rest...) } } }
    return nil
}
func readBOM(items map[string]*Item,errors *[]string) *BOM {
    bom:=&BOM{map[string][]Link{},map[string][]Link{}}
    for _,row:=range readRows("bom.csv") {
        f:=row.Fields; quantity,scrap:=integer(f[2]),integer(f[3]); reason:=""
        switch { case items[f[0]]==nil: reason="unknown item "+f[0]; case items[f[1]]==nil: reason="unknown item "+f[1]; case quantity<1: reason=fmt.Sprintf("bad quantity %d",quantity); case scrap>50: reason=fmt.Sprintf("bad scrap %d",scrap); case f[0]==f[1]: reason="cycle "+f[0]+" -> "+f[0] }
        if reason=="" { for _,link:=range bom.Children[f[0]] { if link.Child==f[1] { reason="duplicate "+f[0]+" -> "+f[1]; break } } }
        if reason=="" { if path:=bom.path(f[1],f[0],map[string]bool{});path!=nil { reason="cycle "+f[0]+" -> "+strings.Join(path," -> ") } }
        if reason!="" { recordError(errors,"bom.csv",row.Line,reason); continue }
        link:=Link{f[0],f[1],quantity,scrap}; bom.Children[link.Parent]=append(bom.Children[link.Parent],link); bom.Parents[link.Child]=append(bom.Parents[link.Child],link)
        sort.Slice(bom.Children[link.Parent],func(i,j int)bool { return bom.Children[link.Parent][i].Child<bom.Children[link.Parent][j].Child }); sort.Slice(bom.Parents[link.Child],func(i,j int)bool { return bom.Parents[link.Child][i].Parent<bom.Parents[link.Child][j].Parent })
    }
    return bom
}
func (bom *BOM) structure(items map[string]*Item) (map[string]int,map[string]int,[]string) {
    codes,cumulative:=map[string]int{},map[string]int{}
    var code,lead func(string)int
    code=func(id string)int { if value,ok:=codes[id];ok { return value }; value:=0; for _,link:=range bom.Parents[id] { value=max(value,code(link.Parent)+1) }; codes[id]=value; return value }
    lead=func(id string)int { if value,ok:=cumulative[id];ok { return value }; value:=0; for _,link:=range bom.Children[id] { value=max(value,lead(link.Child)) }; value+=items[id].Lead; cumulative[id]=value; return value }
    order:=sortedKeys(items); for _,id:=range order { code(id); lead(id) }; sort.Slice(order,func(i,j int)bool { if codes[order[i]]!=codes[order[j]] { return codes[order[i]]<codes[order[j]] }; return order[i]<order[j] }); return codes,cumulative,order
}
