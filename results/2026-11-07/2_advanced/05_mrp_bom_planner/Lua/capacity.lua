local item_module=require("items")
local M={}
function M.read_centers(errors)
    local centers={}
    for _,row in ipairs(item_module.rows("workcenters.csv")) do
        local f=row.fields; local efficiency=tonumber(f[3]); local message
        if centers[f[1]] then message="duplicate center "..f[1]
        elseif efficiency<50 or efficiency>150 then message="bad efficiency "..efficiency end
        if message then item_module.error(errors,"workcenters.csv",row.line,message)
        else centers[f[1]]={id=f[1],minutes=tonumber(f[2]),efficiency=efficiency,available=tonumber(f[2])*efficiency//100,description=f[4]} end
    end
    return centers
end
function M.read_routings(items,centers,bom,errors)
    local routings={}
    for _,row in ipairs(item_module.rows("routings.csv")) do
        local f=row.fields; local number,run=tonumber(f[2]),tonumber(f[5]); local message
        if not items[f[1]] then message="unknown item "..f[1]
        elseif not centers[f[3]] then message="unknown center "..f[3]
        elseif #bom.children[f[1]] == 0 then message="purchased item "..f[1]
        elseif run<1 then message="bad run time "..run
        else for _,operation in ipairs(routings[f[1]] or {}) do if operation.number == number then message="duplicate "..f[1].." operation "..number; break end end end
        if message then item_module.error(errors,"routings.csv",row.line,message)
        else routings[f[1]]=routings[f[1]] or {}; table.insert(routings[f[1]],{number=number,center=f[3],setup=tonumber(f[4]),run=run}) end
    end
    for _,operations in pairs(routings) do table.sort(operations,function(a,b) return a.number<b.number end) end
    return routings
end
function M.week(receipt,lead,index,count) return math.max(receipt-lead+(index*lead)//count,1) end
function M.level(loads,available,horizon)
    local leveled,carry={},0
    for week=horizon,2,-1 do local total=loads[week]+carry; leveled[week]=math.min(total,available); carry=total-leveled[week] end
    leveled[1]=loads[1]+carry; return leveled
end
return M
