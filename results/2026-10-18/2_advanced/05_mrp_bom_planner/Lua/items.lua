local M={}
function M.rows(name)
    local rows={}; local number=0
    for line in io.lines("input/"..name) do number=number+1; if number>1 then local fields={}; for field in (line..","):gmatch("(.-),") do fields[#fields+1]=field end; rows[#rows+1]={line=number,fields=fields} end end
    return rows
end
function M.error(errors,file,line,message) errors[#errors+1]=file.." line "..line..": "..message end
function M.keys(map) local result={}; for key in pairs(map) do result[#result+1]=key end; table.sort(result); return result end
function M.read(errors)
    local items={}; local valid={LFL=true,FOQ=true,POQ=true,MIN=true}
    for _,row in ipairs(M.rows("items.csv")) do
        local f=row.fields; local rule=f[3]; local first,second=f[4]:match("^(%d+)/(%d+)$"); if not first then first=f[4]:match("^%d+$") end
        local a,b=tonumber(first),tonumber(second)
        local fits=(rule == "LFL" and a == 0 and not b) or ((rule == "FOQ" or rule == "POQ") and a and a>=1 and not b) or (rule == "MIN" and a and b and a>=1 and b>=1)
        local message
        if items[f[1]] then message="duplicate item "..f[1]
        elseif not valid[rule] then message="unknown lot rule "..rule
        elseif not fits then message="bad lot parameter "..f[4].." for "..rule end
        if message then M.error(errors,"items.csv",row.line,message)
        else items[f[1]]={id=f[1],lead=tonumber(f[2]),rule=rule,a=a,b=b,safety=tonumber(f[5]),on_hand=tonumber(f[6]),material=tonumber(f[7]),labor=tonumber(f[8]),description=f[9]} end
    end
    return items
end
function M.lot_label(item)
    if item.rule == "MIN" then return "MIN "..item.a.."/"..item.b end
    if item.rule == "LFL" then return "LFL" end
    return item.rule.." "..item.a
end
return M
