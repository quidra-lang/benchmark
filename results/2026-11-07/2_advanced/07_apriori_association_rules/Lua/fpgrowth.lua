local baskets=require("baskets")
local M = {}
local function tree(base,minimum)
 local supports={};for _,p in ipairs(base) do for _,i in ipairs(p.items) do supports[i]=(supports[i] or 0)+p.weight end end
 local t={header={},root={children={}},links={},nodes=0};for i,count in pairs(supports) do if count>=minimum then t.header[#t.header+1]=i end end
 table.sort(t.header,function(a,b) return supports[a]~=supports[b] and supports[a]>supports[b] or supports[a]==supports[b] and a<b end)
 local order={};for j,i in ipairs(t.header) do order[i]=j;t.links[i]={} end
 for _,p in ipairs(base) do
  local path={};for _,i in ipairs(p.items) do if order[i] then path[#path+1]=i end end;table.sort(path,function(a,b) return order[a]<order[b] end);local node=t.root
  for _,i in ipairs(path) do local child=node.children[i];if not child then child={item=i,count=0,parent=node,children={}};node.children[i]=child;t.links[i][#t.links[i]+1]=child;t.nodes=t.nodes+1 end;child.count=child.count+p.weight;node=child end
 end
 return t
end
local function conditional(t,item)
 local base={};for _,node in ipairs(t.links[item]) do
  local reverse={};local ancestor=node.parent;while ancestor~=t.root do reverse[#reverse+1]=ancestor.item;ancestor=ancestor.parent end
  local path={};for j=#reverse,1,-1 do path[#path+1]=reverse[j] end;base[#base+1]={items=path,weight=node.count}
 end;return base
end
function M.grow(data,taxonomy,minimum,max_size)
 local base={};for _,b in ipairs(data) do base[#base+1]={items=baskets.items(b,taxonomy,false),weight=1} end
 local root=tree(base,minimum);local result={header=#root.header,nodes=root.nodes,trees=0,conditional_nodes=0,entries={}};local stack={{tree=root,suffix={}}}
 while #stack>0 do
  local frame=table.remove(stack);local current=frame.tree
  for j=#current.header,1,-1 do
   local item=current.header[j];local set=baskets.union(frame.suffix,{item});local count=0;for _,node in ipairs(current.links[item]) do count=count+node.count end;result.entries[#result.entries+1]={set=set,count=count}
   if #set<max_size then local sub=tree(conditional(current,item),minimum);if sub.nodes>0 then stack[#stack+1]={tree=sub,suffix=set};result.trees=result.trees+1;result.conditional_nodes=result.conditional_nodes+sub.nodes end end
  end
 end
 table.sort(result.entries,function(a,b) return #a.set~=#b.set and #a.set<#b.set or #a.set==#b.set and baskets.compare(a.set,b.set)<0 end)
 return result
end
return M
