local M = {}
local function new() local b={};for i=1,61 do b[i]="." end;return b end
local function place(b,p,c) b[math.min(60,math.max(0,p))+1]=c end
local function framed(center) local b=new();place(b,0,":");place(b,60,":");place(b,center,"|");return b end
local function rounded(v) return math.floor(v+0.5) end
function M.limits(l,v,signalled)
 local span=l.ucl-l.lcl;local b=framed(rounded(60*((l.cl-l.lcl)/span)));place(b,rounded(60*((v-l.lcl)/span)),signalled and "*" or "o");return table.concat(b)
end
function M.cusum(upper,lower,h,up,down)
 local b=framed(30)
 if lower>0 then place(b,30-math.min(30,rounded(30*(lower/h))),down and "*" or "-") end
 if upper>0 then place(b,30+math.min(30,rounded(30*(upper/h))),up and "*" or "+") end
 return table.concat(b)
end
function M.width(scale,width,value,center,signalled)
 local b=new();local e=math.min(30,rounded(30*(width/scale)));place(b,30,"|");place(b,30-e,":");place(b,30+e,":");local d=(value-center)/scale;place(b,30+rounded(30*d),signalled and "*" or "o");return table.concat(b)
end
function M.standard(z,ok) local b=framed(30);place(b,30+rounded(10*z),ok and "o" or "*");return table.concat(b) end
return M
