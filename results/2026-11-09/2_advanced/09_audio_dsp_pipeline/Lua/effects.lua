local signals=require("signals")
local M = {}
function M.gain(x,num,den) local y,c={}, {count=0};for j,v in ipairs(x) do y[j]=signals.sat(signals.rdiv(v*num,den),c) end;return y,c.count end
function M.mix(tracks,weights,den)
 local length=0;for _,s in ipairs(tracks) do length=math.max(length,#s.samples) end;local y,c={}, {count=0}
 for j=1,length do local total=0;for k,s in ipairs(tracks) do total=total+weights[k]*(s.samples[j] or 0) end;y[j]=signals.sat(signals.rdiv(total,den),c) end;return y,c.count
end
function M.delay(x,count) local y={};for n=1,count do y[n]=0 end;for j,v in ipairs(x) do y[j+count]=v end;return y end
function M.echo(x,lag,num,den,tail)
 local y,c={}, {count=0};for j=1,#x+tail do y[j]=x[j] or 0 end;for j=lag+1,#y do y[j]=signals.sat(y[j]+signals.rdiv(num*y[j-lag],den),c) end;return y,c.count
end
function M.resample(x,old_rate,new_rate)
 local length=(#x-1)*new_rate//old_rate+1;local y={};for j=0,length-1 do local position=j*old_rate;local p,q=position//new_rate,position%new_rate;local v=x[p+1];if q>0 then v=v+signals.rdiv((x[p+2]-x[p+1])*q,new_rate) end;y[j+1]=v end;return y
end
function M.fade(x,fade_in,fade_out)
 local y={};for j,v in ipairs(x) do y[j]=v end;for j=0,fade_in-1 do y[j+1]=signals.rdiv(y[j+1]*j,fade_in) end;for j=#y-fade_out,#y-1 do y[j+1]=signals.rdiv(y[j+1]*(#y-1-j),fade_out) end;return y
end
return M
