local M = {}
local function indices(mean,sigma,s)
 local p=(s.usl-s.lsl)/(6*sigma);local u=(s.usl-mean)/(3*sigma);local l=(mean-s.lsl)/(3*sigma)
 return p,u,l,math.min(u,l)
end
local function interval(x,n,z)
 local d=z*math.sqrt(1/(9*n)+x*x/(2*(n-1)));return {x-d,x+d}
end
function M.compute(chosen,groups,s,c)
 local r={values={},below=0,above=0};local total,ranges,sd=0,0,0.0
 for _,i in ipairs(chosen) do local g=groups[i];for _,v in ipairs(g.values) do r.values[#r.values+1]=v end;total=total+g.total;ranges=ranges+g.range;sd=sd+g.sd end
 r.count=#r.values;r.mean=total/r.count;r.sigma_within=(ranges/#chosen)/c.d2;r.sigma_sbar=(sd/#chosen)/c.c4
 local squares=0.0;for _,v in ipairs(r.values) do local d=v-r.mean;squares=squares+d*d;if v<s.lsl then r.below=r.below+1 end;if v>s.usl then r.above=r.above+1 end end
 r.sigma_overall=math.sqrt(squares/(r.count-1));r.cp,r.cpu,r.cpl,r.cpk=indices(r.mean,r.sigma_within,s);r.pp,r.ppu,r.ppl,r.ppk=indices(r.mean,r.sigma_overall,s)
 local d=r.mean-s.target;r.cpm=(s.usl-s.lsl)/(6*math.sqrt(r.sigma_overall*r.sigma_overall+d*d));r.cpk_ci=interval(r.cpk,r.count,s.ci_z);r.ppk_ci=interval(r.ppk,r.count,s.ci_z);r.ppm=(1000000*(r.below+r.above))/r.count
 r.verdict=r.cpk>=1.33 and "capable" or r.cpk>=1 and "marginal" or "incapable"
 return r
end
function M.histogram(values,s)
 local low,high=s.lsl,s.usl
 for _,v in ipairs(values) do low=math.min(low,v);high=math.max(high,v) end
 local width=s.histogram_bin;low=width*(low//width);high=width*(high//width)+width
 local counts={};for a=low,high-width,width do counts[a]=0 end
 local top=0;for _,v in ipairs(values) do local a=low+((v-low)//width)*width;counts[a]=counts[a]+1;top=math.max(top,counts[a]) end
 local rows={};local points={{"lsl",s.lsl},{"target",s.target},{"usl",s.usl}}
 for a=low,high-width,width do
  local b,count=a+width-1,counts[a];local row={"bin",a,b,count}
  if count>0 then row[#row+1]=string.rep("#",(50*count+top-1)//top) end
  for _,p in ipairs(points) do if a<=p[2] and p[2]<=b then row[#row+1]=p[1] end end
  rows[#rows+1]=table.concat(row," ")
 end
 return rows
end
return M
