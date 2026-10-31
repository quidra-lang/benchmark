local baskets=require("baskets")
local M = {}
local function without(set,index) local out={};for j,i in ipairs(set) do if j~=index then out[#out+1]=i end end;return out end
function M.candidates(previous,size,taxonomy,exclude)
 local r={joined=0,excluded=0,pruned=0,sets={}};local known={};for _,e in ipairs(previous) do known[baskets.key(e.set)]=true end
 for j,a in ipairs(previous) do
  for k=j+1,#previous do
   local b=previous[k];local same=true;for p=1,size-2 do if a.set[p]~=b.set[p] then same=false;break end end;if not same then break end
   local set={};for _,i in ipairs(a.set) do set[#set+1]=i end;set[#set+1]=b.set[#b.set];r.joined=r.joined+1
   if exclude and size==2 and (taxonomy[set[1]]==set[2] or taxonomy[set[2]]==set[1]) then r.excluded=r.excluded+1
   else local pruned=false;for p=1,#set do if not known[baskets.key(without(set,p))] then pruned=true;break end end;if pruned then r.pruned=r.pruned+1 else r.sets[#r.sets+1]=set end end
  end
 end
 table.sort(r.sets,function(a,b) return baskets.compare(a,b)<0 end);return r
end
function M.count(support,sets,minimum)
 local result={};for _,set in ipairs(sets) do local count=support:count(set);if count>=minimum then result[#result+1]={set=set,count=count} end end;return result
end
return M
