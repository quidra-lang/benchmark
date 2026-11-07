module Daycount

using ..DatesCalendar: civil, number, leap, monthlength
const CONVENTIONS = ("30/360", "30E/360", "ACT/360", "ACT/365F", "ACT/ACT")

function fraction(convention, start, finish)
    y1, m1, d1 = civil(start)
    y2, m2, d2 = civil(finish)
    if convention == "30/360"
        february = m1 == 2 && d1 == monthlength(y1, m1)
        february && m2 == 2 && d2 == monthlength(y2, m2) && (d2 = 30)
        february && (d1 = 30)
        d2 == 31 && d1 >= 30 && (d2 = 30)
        d1 == 31 && (d1 = 30)
    elseif convention == "30E/360"
        d1, d2 = min(d1, 30), min(d2, 30)
    elseif convention == "ACT/360"
        return finish - start, 360
    elseif convention == "ACT/365F"
        return finish - start, 365
    else
        numerator, year = 0, y1
        while start < finish
            boundary = min(number(year + 1, 1, 1), finish)
            numerator += (leap(year) ? 365 : 366) * (boundary - start)
            start, year = boundary, year + 1
        end
        return numerator, 133590
    end
    return 360 * (y2 - y1) + 30 * (m2 - m1) + d2 - d1, 360
end

end
