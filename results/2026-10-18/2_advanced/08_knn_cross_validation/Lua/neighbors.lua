local M = {}
function M.distance(a,b,metric)
 local total,dot,aa,bb=0.0,0.0,0.0,0.0
 for j,x in ipairs(a) do local y=b[j];local d=x-y;if metric=="squared_euclidean" then total=total+d*d elseif metric=="manhattan" then total=total+math.abs(d) elseif metric=="chebyshev" then total=math.max(total,math.abs(d)) else dot=dot+x*y;aa=aa+x*x;bb=bb+y*y end end
 if metric=="cosine" then local na,nb=math.sqrt(aa),math.sqrt(bb);if na==0 or nb==0 then return 1.0 end;return 1-dot/(na*nb) end;return total
end
function M.sort(order) table.sort(order,function(a,b) return a.distance~=b.distance and a.distance<b.distance or a.distance==b.distance and a.row.id<b.row.id end) end
function M.order(query,rows,vectors,metric)
 local order={};for j,r in ipairs(rows) do order[#order+1]={row=r,distance=M.distance(query,vectors[j],metric)} end;M.sort(order);return order
end
function M.predict(order,k,weighting)
 local nearest={};for j=1,math.min(k,#order) do nearest[j]=order[j] end
 local tallies={};local weight_total,targets,weighted=0.0,0.0,0.0
 for _,n in ipairs(nearest) do local w=1/(n.distance+0.000000001);local label=n.row.label;local t=tallies[label];if not t then t={label=label,count=0,distance=0.0,weight=0.0};tallies[label]=t end;t.count=t.count+1;t.distance=t.distance+n.distance;t.weight=t.weight+w;weight_total=weight_total+w;targets=targets+n.row.target;weighted=weighted+w*n.row.target end
 local ranked={};for _,t in pairs(tallies) do ranked[#ranked+1]=t end
 table.sort(ranked,function(a,b) if weighting=="uniform" then if a.count~=b.count then return a.count>b.count end elseif a.weight~=b.weight then return a.weight>b.weight end;if a.distance~=b.distance then return a.distance<b.distance end;return a.label<b.label end)
 local function share(t) return weighting=="uniform" and t.count/#nearest or t.weight/weight_total end
 local p={label=ranked[1].label,share=share(ranked[1]),runner="",runner_share=0.0,estimate=weighting=="uniform" and targets/#nearest or weighted/weight_total,neighbors=nearest}
 if #ranked>1 then p.runner=ranked[2].label;p.runner_share=share(ranked[2]) end;return p
end
return M
