local M = {}
function M.zones(l)
 local a,b=(l.ucl-l.cl)/3,(l.cl-l.lcl)/3
 return {lcl=l.lcl,cl=l.cl,ucl=l.ucl,u1=l.cl+a,u2=l.cl+2*a,l1=l.cl-b,l2=l.cl-2*b}
end
function M.zone(l,v)
 local z=M.zones(l)
 if v>z.ucl then return "OUT+" elseif v<z.lcl then return "OUT-" elseif v>z.u2 then return "A+" elseif v>z.u1 then return "B+" elseif v>z.cl then return "C+" elseif v<z.l2 then return "A-" elseif v<z.l1 then return "B-" elseif v<z.cl then return "C-" end
 return "C0"
end
function M.check(chart,seq,l,rules)
 local lengths={1,3,5,8,6,14,15,8};local z=M.zones(l);local signals={}
 for k=1,#seq.values do
  for _,rule in ipairs(rules) do
   local length=lengths[rule]
   if k>=length then
    local first=k-length+1;local v=seq.values[k];local direction
    if rule==1 then if v>z.ucl or v<z.lcl then direction=v>z.cl and "UP" or "DOWN" end
    elseif rule==2 or rule==3 then
     local u,d,needed=z.u2,z.l2,2;if rule==3 then u,d,needed=z.u1,z.l1,4 end
     local up,down=0,0;for j=first,k do local x=seq.values[j];if x>u then up=up+1 end;if x<d then down=down+1 end end
     if v>u and up>=needed then direction="UP" elseif v<d and down>=needed then direction="DOWN" end
    elseif rule==4 or rule==5 then
     local up,down=true,true
     for j=first+(rule==5 and 1 or 0),k do local x=seq.values[j];local previous=rule==5 and seq.values[j-1] or z.cl;up=up and x>previous;down=down and x<previous end
     if up then direction="UP" elseif down then direction="DOWN" end
    elseif rule==6 then
     local ok,previous=true,0
     for j=first+1,k do local d=seq.values[j]-seq.values[j-1];if d==0 or j>first+1 and (d>0)==(previous>0) then ok=false end;previous=d end
     if ok then direction="NONE" end
    elseif rule==7 then
     local ok=true;for j=first,k do local x=seq.values[j];ok=ok and z.l1<x and x<z.u1 end;if ok then direction="NONE" end
    else
     local ok,up,down=true,false,false;for j=first,k do local x=seq.values[j];ok=ok and (x>z.u1 or x<z.l1);up=up or x>z.u1;down=down or x<z.l1 end;if ok and up and down then direction="NONE" end
    end
    if direction then signals[#signals+1]={chart=chart,rule=rule,start=seq.numbers[first],finish=seq.numbers[k],value=v,direction=direction} end
   end
  end
 end
 return signals
end
return M
