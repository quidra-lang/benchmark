local baskets=require("baskets")
local M = {}
local function gcd(a,b) a=math.abs(a);while b~=0 do a,b=b,a%b end;return a end
function M.fraction(n,d) if d<0 then n,d=-n,-d end;local g=gcd(n,d);return {n=n//g,d=d//g} end
function M.compare(a,b) local x,y=a.n*b.d,b.n*a.d;return x==y and 0 or x<y and -1 or 1 end
function M.subtract(a,b) return M.fraction(a.n*b.d-b.n*a.d,a.d*b.d) end
function M.lift(total,together,first,second) return M.fraction(total*together,first*second) end
function M.thresholds(confidence,lift,p) return M.compare(confidence,p.min_confidence)>=0 and M.compare(lift,p.min_lift)>=0 end
function M.metrics(set,x,y,count,total,nx,ny)
 local r={set=set,x=x,y=y,count=count,support=M.fraction(count,total),confidence=M.fraction(count,nx),lift=M.lift(total,count,nx,ny),leverage=M.fraction(total*count-nx*ny,total*total)}
 if nx~=count then r.conviction=M.fraction((total-ny)*nx,total*(nx-count)) end;return r
end
function M.order(a,b)
 local c=M.compare(a.confidence,b.confidence);if c~=0 then return c>0 end;c=M.compare(a.lift,b.lift);if c~=0 then return c>0 end
 if a.count~=b.count then return a.count>b.count end;c=baskets.compare(a.x,b.x);if c~=0 then return c<0 end;return baskets.compare(a.y,b.y)<0
end
return M
