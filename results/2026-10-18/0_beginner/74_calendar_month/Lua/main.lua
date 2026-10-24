local month_names = {"January","February","March","April","May","June","July","August","September","October","November","December"}
for index,pair in ipairs({{2024,2},{2026,8},{2026,11}}) do
    local year,month = table.unpack(pair)
    if index > 1 then io.write("\n") end
    io.write(string.format("%s %d\nSu Mo Tu We Th Fr Sa\n",month_names[month],year))
    local adjusted_year = month < 3 and year-1 or year
    local adjusted_month = month < 3 and month+12 or month
    local century,within = adjusted_year//100,adjusted_year%100
    local weekday = (1+(13*(adjusted_month+1))//5+within+within//4+century//4+5*century+6)%7
    local leap = year%4 == 0 and (year%100 ~= 0 or year%400 == 0)
    local days = month == 2 and leap and 29 or ({31,28,31,30,31,30,31,31,30,31,30,31})[month]
    local fields = {}
    for i = 1,weekday do fields[#fields+1] = "  " end
    for day = 1,days do
        fields[#fields+1] = string.format("%2d",day)
        if #fields == 7 or day == days then
            io.write(table.concat(fields," "),"\n")
            fields = {}
        end
    end
end
