local M = {}
function M.subgroups(values,n)
 local groups={}
 for first=1,#values,n do
  local g={values={},total=0,squares=0}; local low,high=values[first],values[first]
  for i=first,first+n-1 do local v=values[i];g.values[#g.values+1]=v;g.total=g.total+v;g.squares=g.squares+v*v;low=math.min(low,v);high=math.max(high,v) end
  g.range=high-low;g.mean=g.total/n;g.sd=math.sqrt((n*g.squares-g.total*g.total)/(n*(n-1)));groups[#groups+1]=g
 end
 return groups
end
function M.limits(f,chosen,groups,values,n,c)
 local total,spread,sd=0,0,0.0
 if f==3 then
  for j,t in ipairs(chosen) do total=total+values[t];if j>1 then spread=spread+math.abs(values[t]-values[chosen[j-1]]) end end
  local mean,r=total/#chosen,spread/(#chosen-1)
  return {{lcl=mean-3*r/1.128,cl=mean,ucl=mean+3*r/1.128},{lcl=0*r,cl=r,ucl=3.267*r}}
 end
 for _,i in ipairs(chosen) do local g=groups[i];total=total+g.total;spread=spread+g.range;sd=sd+g.sd end
 local mean=total/(#chosen*n)
 if f==1 then local r=spread/#chosen;return {{lcl=mean-c.a2*r,cl=mean,ucl=mean+c.a2*r},{lcl=c.d3*r,cl=r,ucl=c.d4*r}} end
 sd=sd/#chosen;return {{lcl=mean-c.a3*sd,cl=mean,ucl=mean+c.a3*sd},{lcl=c.b3*sd,cl=sd,ucl=c.b4*sd}}
end
function M.series(f,chosen,groups,values)
 local a,b={numbers={},values={}},{numbers={},values={}}
 for j,t in ipairs(chosen) do
  a.numbers[#a.numbers+1]=t
  if f==3 then a.values[#a.values+1]=values[t];if j>1 then b.numbers[#b.numbers+1]=t;b.values[#b.values+1]=math.abs(values[t]-values[chosen[j-1]]) end
  else local g=groups[t];a.values[#a.values+1]=g.mean;b.numbers[#b.numbers+1]=t;b.values[#b.values+1]=f==1 and g.range or g.sd end
 end
 return {a,b}
end
function M.outside(l,v) return v<l.lcl or v>l.ucl end
return M
