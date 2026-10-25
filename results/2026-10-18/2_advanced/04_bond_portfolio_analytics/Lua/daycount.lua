local dates=require("dates_calendar")
local M={}
function M.fraction(kind,start,finish)
    if kind == "ACT/360" then return finish-start,360 end
    if kind == "ACT/365F" then return finish-start,365 end
    local y1,m1,d1=dates.civil(start); local y2,m2,d2=dates.civil(finish)
    if kind == "ACT/ACT" then
        local leap,other=0,0
        while start<finish do
            local boundary=math.min(dates.day(y1+1,1,1),finish)
            if dates.leap(y1) then leap=leap+boundary-start else other=other+boundary-start end
            start=boundary; y1=y1+1
        end
        return 365*leap+366*other,133590
    end
    if kind == "30/360" then
        local feb1=m1 == 2 and d1 == dates.month_length(y1,m1)
        if feb1 and m2 == 2 and d2 == dates.month_length(y2,m2) then d2=30 end
        if feb1 then d1=30 end
        if d2 == 31 and d1>=30 then d2=30 end
        if d1 == 31 then d1=30 end
    else d1=math.min(d1,30); d2=math.min(d2,30) end
    return 360*(y2-y1)+30*(m2-m1)+d2-d1,360
end
return M
