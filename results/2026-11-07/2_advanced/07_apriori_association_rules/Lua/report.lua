local M = {}
function M.fraction(value)
 local negative=value.n<0;local n=math.abs(value.n);local scaled=10000*n//value.d
 return string.format("%s%d/%d=%s%d.%04d",negative and "-" or "",n,value.d,negative and scaled>0 and "-" or "",scaled//10000,scaled%10000)
end
function M.percent(part,whole) local scaled=10000*part//whole;return string.format("%d.%02d%%",scaled//100,scaled%100) end
function M.money(cents) return string.format("%d.%02d",cents//100,cents%100) end
function M.itemset(set,names) local out={};for _,i in ipairs(set) do out[#out+1]=names[i] end;return table.concat(out,"+") end
function M.arrow(r,names) return M.itemset(r.x,names).." -> "..M.itemset(r.y,names) end
function M.rules_csv(rules,names)
 local lines={"rank,antecedent,consequent,count,support,confidence,lift,leverage,conviction,improvement"}
 for _,r in ipairs(rules) do lines[#lines+1]=table.concat({r.rank,M.itemset(r.x,names),M.itemset(r.y,names),r.count,M.fraction(r.support),M.fraction(r.confidence),M.fraction(r.lift),M.fraction(r.leverage),r.conviction and M.fraction(r.conviction) or "INF",M.fraction(r.improvement)},",") end;return lines
end
function M.write(name,lines)
 local file=assert(io.open("output/"..name,"w"));for _,line in ipairs(lines) do file:write(line,"\n") end;file:close()
end
return M
