local M={}
function M.money(cents) return string.format("%d.%02d",cents//100,cents%100) end
function M.percent(part,whole) return (200*part+whole)//(2*whole) end
function M.row(label,values,width)
    local parts={string.format("%-10s",label)}; for _,value in ipairs(values) do parts[#parts+1]=string.format("%"..width.."d",value) end; return table.concat(parts)
end
function M.write(name,lines)
    local file=assert(io.open("output/"..name,"w")); for _,line in ipairs(lines) do file:write(line,"\n") end; file:close()
end
return M
