local M = {}
function M.fixed(v,places) local text=string.format("%."..(places or 4).."f",v);if text:sub(1,1)=="-" and tonumber(text)==0 then return text:sub(2) end;return text end
function M.four(v) return tonumber(M.fixed(v,4)) end
function M.ratio(a,b) return string.format("%d/%d %s",a,b,M.fixed(a/b)) end
function M.fraction(a,b)
 if b==0 then return "- -" end;local x,y=a,b;while y~=0 do x,y=y,x%y end;return string.format("%d/%d %s",a//x,b//x,M.fixed(a/b))
end
function M.write(name,lines) local file=assert(io.open("output/"..name,"w"));for _,line in ipairs(lines) do file:write(line,"\n") end;file:close() end
return M
