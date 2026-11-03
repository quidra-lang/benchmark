local M = {}
function M.gcd(a,b) while b~=0 do a,b=b,a%b end; return a end
function M.dec(a,b,d)
    if b==0 then return '-' end
    local scale=1; for _=1,d do scale=scale*10 end
    local z=(2*a*scale+b)//(2*b)
    return string.format('%d.%0'..d..'d',z//scale,z%scale)
end
function M.frac(a,b)
    if b==0 then return '-' end
    local g=M.gcd(a,b); return string.format('%d/%d',a//g,b//g)
end
function M.percentile(times,q) return times[(q*#times+99)//100] end
function M.histogram(times,width)
    local first,last=times[1]//width,times[#times]//width; local counts={}; for i=first,last do counts[i]=0 end
    local largest=0
    for _,time in ipairs(times) do local bin=time//width; counts[bin]=counts[bin]+1; largest=math.max(largest,counts[bin]) end
    local lines={}
    for i=first,last do
        local count=counts[i]; local low=i*width; local line=string.format('  %d-%d %d',low,low+width-1,count); local stars=(80*count+largest)//(2*largest)
        if stars>0 then line=line..' '..string.rep('*',stars) end
        lines[#lines+1]=line
    end
    return lines
end
return M
