local function days_in_month(year,month)
    local leap = year%400 == 0 or (year%4 == 0 and year%100 ~= 0)
    if month == 2 and leap then return 29 end
    return ({31,28,31,30,31,30,31,31,30,31,30,31})[month]
end
for _, pair in ipairs({{"1999-12-25",10},{"2000-02-27",3},{"2021-02-20",14},{"2023-11-15",120},{"2026-10-17",1500}}) do
    local original,added = pair[1],pair[2]
    local year,month,day = original:match("(%d+)%-(%d+)%-(%d+)")
    year,month,day = tonumber(year),tonumber(month),tonumber(day)
    for step = 1,added do
        day = day+1
        if day > days_in_month(year,month) then
            day = 1; month = month+1
            if month > 12 then month = 1; year = year+1 end
        end
    end
    io.write(string.format("%s + %d days = %04d-%02d-%02d\n",original,added,year,month,day))
end
