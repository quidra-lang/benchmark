using Printf
function main()
    month_names = ["January","February","March","April","May","June","July","August","September","October","November","December"]
    for (index,(year,month)) in enumerate([(2024,2),(2026,8),(2026,11)])
        index > 1 && println()
        println(month_names[month]," ",year)
        println("Su Mo Tu We Th Fr Sa")
        adjusted_year = month < 3 ? year-1 : year
        adjusted_month = month < 3 ? month+12 : month
        century,within = divrem(adjusted_year,100)
        weekday = mod(1+div(13*(adjusted_month+1),5)+within+div(within,4)+div(century,4)+5*century+6,7)
        leap = year%4 == 0 && (year%100 != 0 || year%400 == 0)
        days = month == 2 && leap ? 29 : [31,28,31,30,31,30,31,31,30,31,30,31][month]
        fields = fill("  ",weekday)
        for day in 1:days
            push!(fields,@sprintf("%2d",day))
            if length(fields) == 7 || day == days
                println(join(fields," "))
                empty!(fields)
            end
        end
    end
end
main()
