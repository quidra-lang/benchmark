local scaling=require("scaling")
local neighbors=require("neighbors")
local M = {}
function M.notation(m) return string.format("k=%d metric=%s weighting=%s scaling=%s",m.k,m.metric,m.weighting,m.scaling) end
function M.stratified(rows,count)
 local order={};for j=1,#rows do order[j]=j end;table.sort(order,function(i,j) local a,b=rows[i],rows[j];return a.label~=b.label and a.label<b.label or a.label==b.label and a.id<b.id end)
 local folds={};for f=1,count do folds[f]={} end;for position,j in ipairs(order) do local f=(position-1)%count+1;folds[f][#folds[f]+1]=j end;for _,fold in ipairs(folds) do table.sort(fold) end;return folds
end
function M.training(rows,excluded)
 local skip,out={},{};for _,i in ipairs(excluded) do skip[i]=true end;for j,r in ipairs(rows) do if not skip[j] then out[#out+1]=r end end;return out
end
function M.orders(train,queries,method,metric,features)
 local s=scaling.compute(train,method);local vectors={};for j,r in ipairs(train) do vectors[j]=scaling.transform(s,r,features) end;local orders={};for j,r in ipairs(queries) do orders[j]=neighbors.order(scaling.transform(s,r,features),train,vectors,metric) end;return orders
end
function M.predict(m,train,queries,features)
 local orders=M.orders(train,queries,m.scaling,m.metric,features);local out={};for j,order in ipairs(orders) do out[j]=neighbors.predict(order,m.k,m.weighting) end;return out
end
function M.rmse(errors) local sum=0.0;for _,v in ipairs(errors) do sum=sum+v*v end;return math.sqrt(sum/#errors) end
function M.mae(errors) local sum=0.0;for _,v in ipairs(errors) do sum=sum+math.abs(v) end;return sum/#errors end
function M.r_squared(errors,targets)
 local sum=0.0;for _,v in ipairs(targets) do sum=sum+v end;local mean=sum/#targets;local residual,spread=0.0,0.0;for _,v in ipairs(errors) do residual=residual+v*v end;for _,v in ipairs(targets) do local d=v-mean;spread=spread+d*d end;return 1-residual/spread
end
return M
