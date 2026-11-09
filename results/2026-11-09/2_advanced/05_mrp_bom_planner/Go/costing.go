package main

import "sort"

type StandardCost struct { Material,Labor,Total int64 }
func standardCosts(items map[string]*Item,bom *BOM,order []string) map[string]StandardCost {
    costs:=map[string]StandardCost{}
    for i:=len(order)-1;i>=0;i-- { id:=order[i]; material,labor:=items[id].Material,items[id].Labor; for _,link:=range bom.Children[id] { child:=costs[link.Child]; material+=(link.Quantity*(100+link.Scrap)*child.Material+50)/100; labor+=(link.Quantity*(100+link.Scrap)*child.Labor+50)/100 }; costs[id]=StandardCost{material,labor,material+labor} }
    return costs
}
func abcClasses(values map[string]int64) map[string]string {
    order:=sortedKeys(values); total:=int64(0); for _,value:=range values { total+=value }
    sort.Slice(order,func(i,j int)bool { if values[order[i]]!=values[order[j]] { return values[order[i]]>values[order[j]] }; return order[i]<order[j] }); classes:=map[string]string{}; before:=int64(0)
    for _,id:=range order { value:=values[id]; class:="C"; if value>0 { if 100*before<80*total { class="A" } else if 100*before<95*total { class="B" } }; classes[id]=class; before+=value }; return classes
}
