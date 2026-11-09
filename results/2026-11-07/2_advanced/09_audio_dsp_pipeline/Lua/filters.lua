local signals=require("signals")
local M = {}
function M.fir(x,divisor,taps)
 local y,c={}, {count=0};for n=0,#x-1 do local total=0;for k=0,#taps-1 do if n>=k then total=total+taps[k+1]*x[n-k+1] end end;y[n+1]=signals.sat(total//divisor,c) end;return y,c.count
end
function M.biquad(x,coefficients)
 local u=x;local c={count=0}
 for first=1,#coefficients,5 do local v={};local b0,b1,b2,a1,a2=table.unpack(coefficients,first,first+4)
  for n=1,#u do local total=b0*u[n];if n>=2 then total=total+b1*u[n-1] end;if n>=3 then total=total+b2*u[n-2] end;if n>=2 then total=total-a1*v[n-1] end;if n>=3 then total=total-a2*v[n-2] end;v[n]=signals.sat(total//16384,c) end;u=v
 end;return u,c.count
end
function M.moving_average(x,width) local y={};local total=0;for n,v in ipairs(x) do total=total+v;if n>width then total=total-x[n-width] end;y[n]=signals.rdiv(total,width) end;return y end
function M.dc_block(x,num,den)
 local y,c={}, {count=0};local previous_x,previous_y=0,0;for n,v in ipairs(x) do y[n]=signals.sat(v-previous_x+signals.rdiv(num*previous_y,den),c);previous_x,previous_y=v,y[n] end;return y,c.count
end
return M
