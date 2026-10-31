local items_module=require("items")
local M={}
function M.need(row,quantity) return (quantity*row.quantity*(100+row.scrap)+99)//100 end
function M.read(items,errors)
    local bom={children={},parents={}}
    for id in pairs(items) do bom.children[id]={}; bom.parents[id]={} end
    local function path(id,target,visited)
        if id == target then return {id} end
        visited[id]=true
        for _,row in ipairs(bom.children[id]) do if not visited[row.child] then
            local rest=path(row.child,target,visited)
            if rest then table.insert(rest,1,id); return rest end
        end end
    end
    for _,input in ipairs(items_module.rows("bom.csv")) do
        local f=input.fields; local quantity,scrap=tonumber(f[3]),tonumber(f[4]); local message
        if not items[f[1]] then message="unknown item "..f[1]
        elseif not items[f[2]] then message="unknown item "..f[2]
        elseif quantity<1 then message="bad quantity "..quantity
        elseif scrap>50 then message="bad scrap "..scrap
        elseif f[1] == f[2] then message="cycle "..f[1].." -> "..f[1]
        else
            for _,row in ipairs(bom.children[f[1]]) do if row.child == f[2] then message="duplicate "..f[1].." -> "..f[2]; break end end
            if not message then local found=path(f[2],f[1],{}); if found then message="cycle "..f[1].." -> "..table.concat(found," -> ") end end
        end
        if message then items_module.error(errors,"bom.csv",input.line,message)
        else
            local row={parent=f[1],child=f[2],quantity=quantity,scrap=scrap}
            table.insert(bom.children[row.parent],row); table.sort(bom.children[row.parent],function(a,b) return a.child<b.child end)
            table.insert(bom.parents[row.child],row); table.sort(bom.parents[row.child],function(a,b) return a.parent<b.parent end)
        end
    end
    return bom
end
function M.structure(items,bom)
    local codes,cumulative={},{}
    local function code(id)
        if codes[id] ~= nil then return codes[id] end
        local value=0; for _,row in ipairs(bom.parents[id]) do value=math.max(value,code(row.parent)+1) end
        codes[id]=value; return value
    end
    local function lead(id)
        if cumulative[id] then return cumulative[id] end
        local value=0; for _,row in ipairs(bom.children[id]) do value=math.max(value,lead(row.child)) end
        cumulative[id]=items[id].lead+value; return cumulative[id]
    end
    local order=items_module.keys(items); for _,id in ipairs(order) do code(id); lead(id) end
    table.sort(order,function(a,b) return codes[a] == codes[b] and a<b or codes[a]<codes[b] end)
    return codes,cumulative,order
end
return M
