local M={}
function M.size(item,week,projected,receipts,gross,horizon)
    local net=item.safety-projected
    if item.rule == "LFL" then return net end
    if item.rule == "FOQ" then return (net+item.a-1)//item.a*item.a end
    if item.rule == "MIN" then return (math.max(net,item.a)+item.b-1)//item.b*item.b end
    local quantity=net
    for later=week+1,math.min(week+item.a-1,horizon) do projected=projected+receipts[later]-gross[later]; quantity=math.max(quantity,item.safety-projected) end
    return quantity
end
return M
