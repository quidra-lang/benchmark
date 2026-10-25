local M={}
local lengths={31,28,31,30,31,30,31,31,30,31,30,31}
function M.leap(year) return year%4 == 0 and (year%100 ~= 0 or year%400 == 0) end
function M.year_length(year) return M.leap(year) and 366 or 365 end
function M.month_length(year,month) return month == 2 and M.leap(year) and 29 or lengths[month] end
function M.split(text) return tonumber(text:sub(1,4)),tonumber(text:sub(6,7)),tonumber(text:sub(9,10)) end
function M.valid(text)
    local year,month,day=M.split(text)
    return year>=2001 and year<=2099 and month>=1 and month<=12 and day>=1 and day<=M.month_length(year,month)
end
function M.day(year,month,day)
    local number=day-1
    for y=2000,year-1 do number=number+M.year_length(y) end
    for m=1,month-1 do number=number+M.month_length(year,m) end
    return number
end
function M.parse(text) return M.day(M.split(text)) end
function M.civil(number)
    local year,month=2000,1
    while number>=M.year_length(year) do number=number-M.year_length(year); year=year+1 end
    while number>=M.month_length(year,month) do number=number-M.month_length(year,month); month=month+1 end
    return year,month,number+1
end
function M.format(number) return string.format("%04d-%02d-%02d",M.civil(number)) end
function M.business(number,holidays) return (number+5)%7<5 and not holidays[number] end
function M.move(number,count,direction,holidays)
    while count>0 do number=number+direction; if M.business(number,holidays) then count=count-1 end end
    return number
end
function M.adjust(number,rule,holidays)
    if rule == "UNADJUSTED" then return number end
    local direction=rule == "PRECEDING" and -1 or 1
    local adjusted=number
    while not M.business(adjusted,holidays) do adjusted=adjusted+direction end
    if rule == "MODIFIED_FOLLOWING" then
        local _,original_month=M.civil(number); local _,adjusted_month=M.civil(adjusted)
        if original_month ~= adjusted_month then return M.adjust(number,"PRECEDING",holidays) end
    end
    return adjusted
end
return M
