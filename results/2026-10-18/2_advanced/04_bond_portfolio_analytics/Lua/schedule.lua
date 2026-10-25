local dates=require("dates_calendar")
local M={}
function M.build(issue,maturity,frequency,eom,long)
    local year,month,day=dates.civil(maturity)
    local end_rule=eom and day == dates.month_length(year,month)
    local descending,boundary={},maturity
    while boundary>issue do
        descending[#descending+1]=boundary
        local index=year*12+month-1-(12//frequency)*#descending
        local y,m=index//12,index%12+1
        local d=end_rule and dates.month_length(y,m) or math.min(day,dates.month_length(y,m))
        boundary=dates.day(y,m,d)
    end
    if long and boundary ~= issue and #descending>=2 then table.remove(descending) end
    local result={issue}; for i=#descending,1,-1 do result[#result+1]=descending[i] end
    return result
end
return M
