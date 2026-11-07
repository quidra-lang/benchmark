local M = {}
function M.center(chart,chosen,lots)
 local d,c,n=0,0,0
 for _,i in ipairs(chosen) do local l=lots[i];d=d+l.defectives;c=c+l.defects;n=n+l.inspected end
 local fraction=d/n;local value=fraction
 if chart==2 then value=d/#chosen elseif chart==3 then value=c/#chosen elseif chart==4 then value=c/n end
 return {value=value,fraction=fraction}
end
function M.point(chart,l,c)
 local v,sigma
 if chart==1 then v=l.defectives/l.inspected;sigma=math.sqrt(c.value*(1-c.value)/l.inspected)
 elseif chart==2 then v=l.defectives;sigma=math.sqrt(c.value*(1-c.fraction))
 elseif chart==3 then v=l.defects;sigma=math.sqrt(c.value)
 else v=l.defects/l.inspected;sigma=math.sqrt(c.value/l.inspected) end
 local p={value=v,lcl=math.max(0,c.value-3*sigma),ucl=c.value+3*sigma,z=(v-c.value)/sigma,status="ok"}
 if v>p.ucl then p.status="high" elseif v<p.lcl then p.status="low" end
 return p
end
return M
