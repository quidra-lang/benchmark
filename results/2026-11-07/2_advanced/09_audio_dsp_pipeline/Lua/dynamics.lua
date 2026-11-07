local signals=require("signals")
local M = {}
function M.envelope(x,attack,release)
 local env={};local e=0;for n,v in ipairs(x) do local a=math.min(math.abs(v),32767);local c=a>e and attack or release;e=e+signals.rdiv((a-e)*c,32768);env[n]=e end;return env
end
function M.normalize(x,target) local p=signals.peak(x);local y={};for n,v in ipairs(x) do y[n]=p>0 and signals.rdiv(v*target,p) or v end;return y,p end
function M.gate(x,threshold,hold)
 local y={};local last=-#x-hold-1;local muted=0;for n,v in ipairs(x) do if math.abs(v)>=threshold then last=n end;if n-last<=hold then y[n]=v else y[n]=0;muted=muted+1 end end;return y,muted
end
function M.compress(x,threshold,ratio_num,ratio_den,attack,release)
 local env=M.envelope(x,attack,release);local y={};local gain,minimum,reduced=32768,32768,0
 for n,v in ipairs(x) do local e=env[n];local target=32768;if e>threshold then local d=threshold+signals.rdiv((e-threshold)*ratio_den,ratio_num);target=signals.rdiv(d*32768,e) end;if target<gain then gain=target else gain=gain+signals.rdiv((target-gain)*release,32768) end;minimum=math.min(minimum,gain);if gain<32768 then reduced=reduced+1 end;y[n]=signals.rdiv(v*gain,32768) end;return y,minimum,reduced
end
return M
