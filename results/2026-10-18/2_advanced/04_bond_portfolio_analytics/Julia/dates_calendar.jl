module DatesCalendar

leap(year) = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
yearlength(year) = leap(year) ? 366 : 365
monthlength(year, month) = month == 2 && leap(year) ? 29 : (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)[month]
parts(text) = (parse(Int, text[1:4]), parse(Int, text[6:7]), parse(Int, text[9:10]))

function valid(text)
    year, month, day = parts(text)
    return 2001 <= year <= 2099 && 1 <= month <= 12 && 1 <= day <= monthlength(year, month)
end

function number(year, month, day)
    result = day - 1
    for previous in 2000:year - 1
        result += yearlength(previous)
    end
    for previous in 1:month - 1
        result += monthlength(year, previous)
    end
    return result
end

parsedate(text) = number(parts(text)...)

function civil(day)
    year, month = 2000, 1
    while day >= yearlength(year)
        day -= yearlength(year)
        year += 1
    end
    while day >= monthlength(year, month)
        day -= monthlength(year, month)
        month += 1
    end
    return year, month, day + 1
end

function formatdate(day)
    year, month, date = civil(day)
    return lpad(string(year), 4, '0') * "-" * lpad(string(month), 2, '0') * "-" * lpad(string(date), 2, '0')
end

struct Calendar
    holidays::Set{Int}
end

business(calendar, day) = mod(day + 5, 7) < 5 && day ∉ calendar.holidays

function move(calendar, day, count)
    step = count < 0 ? -1 : 1
    remaining = count < 0 ? -count : count
    while remaining > 0
        day += step
        business(calendar, day) && (remaining -= 1)
    end
    return day
end

function adjust(calendar, day, rule)
    rule == "UNADJUSTED" && return day
    step = rule == "PRECEDING" ? -1 : 1
    result = day
    while !business(calendar, result)
        result += step
    end
    if rule == "MODIFIED_FOLLOWING" && civil(result)[2] != civil(day)[2]
        return adjust(calendar, day, "PRECEDING")
    end
    return result
end

end
