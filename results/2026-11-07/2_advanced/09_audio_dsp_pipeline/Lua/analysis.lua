local signals=require("signals")
local M = {}
function M.energy(x) local total=0;for _,v in ipairs(x) do total=total+v*v end;return total end
function M.isqrt(n) local low,high=0,n+1;while low+1<high do local middle=low+(high-low)//2;if middle<=n//middle then low=middle else high=middle end end;return low end
function M.rms(x) return M.isqrt(M.energy(x)//#x) end
function M.crossings(x) local count=0;for j=2,#x do if (x[j-1]<0)~=(x[j]<0) then count=count+1 end end;return count end
function M.clipped(x) local count=0;for _,v in ipairs(x) do if v==32767 or v==-32768 then count=count+1 end end;return count end
function M.crest(x)
 local e=M.energy(x);if e==0 then return "none" end;local p=signals.peak(x);local n,d=p*p*#x,e;local a,b=n,d;while b~=0 do a,b=b,a%b end;return string.format("%d/%d",n//a,d//a)
end
function M.pitch(x,low,high)
 local best,largest=low,0;for lag=low,high do local correlation=0;for n=1,#x-lag do correlation=correlation+x[n]*x[n+lag] end;if lag==low or correlation>largest then best,largest=lag,correlation end end;return largest>0 and best or 0
end
function M.decimal_two(h) return string.format("%d.%02d",h//100,h%100) end
function M.frequency(rate,lag) return M.decimal_two(signals.rdiv(100*rate,lag)) end
return M
