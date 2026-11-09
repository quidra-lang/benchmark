local M={}
function M.rollup(items,bom,order)
    local costs={}
    for i=#order,1,-1 do
        local id=order[i]; local material,labor=items[id].material,items[id].labor
        for _,row in ipairs(bom.children[id]) do local child=costs[row.child]; material=material+(row.quantity*(100+row.scrap)*child.material+50)//100; labor=labor+(row.quantity*(100+row.scrap)*child.labor+50)//100 end
        costs[id]={material=material,labor=labor,total=material+labor}
    end
    return costs
end
function M.abc(values)
    local order,total={},0
    for id,value in pairs(values) do order[#order+1]=id; total=total+value end
    table.sort(order,function(a,b) return values[a] == values[b] and a<b or values[a]>values[b] end)
    local classes,before={},0
    for _,id in ipairs(order) do local value=values[id]; classes[id]=value == 0 and "C" or 100*before<80*total and "A" or 100*before<95*total and "B" or "C"; before=before+value end
    return classes
end
return M
