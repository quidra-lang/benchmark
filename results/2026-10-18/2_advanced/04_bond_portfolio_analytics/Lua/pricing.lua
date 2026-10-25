local M={}
function M.bisect(fn,low,high,target)
    for _=1,80 do local middle=(low+high)/2; if fn(middle)>target then low=middle else high=middle end end
    return (low+high)/2
end
function M.values(flows,w,frequency,rate)
    local first=1+w*rate/frequency; local growth=1+rate/frequency
    local factor,result=1.0,{}
    for i,flow in ipairs(flows) do result[i]=flow/(first*factor); factor=factor*growth end
    return result
end
function M.dirty(flows,w,frequency,outstanding,rate)
    local total=0.0; for _,value in ipairs(M.values(flows,w,frequency,rate)) do total=total+value end
    return total*100/outstanding
end
function M.solve(flows,w,frequency,outstanding,target)
    return M.bisect(function(rate) return M.dirty(flows,w,frequency,outstanding,rate) end,0.0,1.0,target)
end
function M.risk(flows,w,frequency,outstanding,rate)
    local total,weighted,curvature=0.0,0.0,0.0
    for i,value in ipairs(M.values(flows,w,frequency,rate)) do
        local years=(i-1+w)/frequency
        total=total+value; weighted=weighted+years*value; curvature=curvature+years*(years+1/frequency)*value
    end
    local growth=1+rate/frequency; local macaulay=weighted/total
    return {macaulay=macaulay,modified=macaulay/growth,convexity=curvature/(total*growth*growth),dv01=(M.dirty(flows,w,frequency,outstanding,rate-0.0001)-M.dirty(flows,w,frequency,outstanding,rate+0.0001))/2}
end
return M
