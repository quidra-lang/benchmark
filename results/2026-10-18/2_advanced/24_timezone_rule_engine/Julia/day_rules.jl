const MONTH_NAMES = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const WEEKDAY_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
const COMMON_MONTH_DAYS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const SECONDS_PER_DAY = 86400
const NEG_INFINITY = -(1 << 62)
const POS_INFINITY = 1 << 62
is_leap_year(year::Int) = year % 4 == 0 && year % 100 != 0 || year % 400 == 0
days_in_month(year::Int, month::Int) = month == 2 && is_leap_year(year) ? 29 : COMMON_MONTH_DAYS[month]
function days_before_year(year::Int)
    previous = year - 1
    previous * 365 + fld(previous, 4) - fld(previous, 100) + fld(previous, 400)
end
function day_number(year::Int, month::Int, day::Int)
    days = days_before_year(year) - days_before_year(1970) + day - 1
    for earlier in 1:(month - 1)
        days += days_in_month(year, earlier)
    end
    days
end
weekday_of(number::Int) = mod(number + 4, 7)
function date_of_day(number::Int)
    year = 1970 + fld(number, 366)
    while day_number(year, 1, 1) > number
        year -= 1
    end
    while day_number(year + 1, 1, 1) <= number
        year += 1
    end
    month = 1
    day = number - day_number(year, 1, 1) + 1
    while day > days_in_month(year, month)
        day -= days_in_month(year, month)
        month += 1
    end
    year, month, day
end
time_value(year::Int, month::Int, day::Int, hour::Int, minute::Int, second::Int) = day_number(year, month, day) * SECONDS_PER_DAY + hour * 3600 + minute * 60 + second
function split_time(time::Int)
    year, month, day = date_of_day(fld(time, SECONDS_PER_DAY))
    seconds = mod(time, SECONDS_PER_DAY)
    year, month, day, seconds ÷ 3600, seconds ÷ 60 % 60, seconds % 60
end
struct DaySpec
    kind::Symbol
    weekday::Int
    day::Int
end
function day_value(spec::DaySpec, year::Int, month::Int)
    if spec.kind == :last
        last_day = day_number(year, month, days_in_month(year, month))
        return last_day - mod(weekday_of(last_day) - spec.weekday, 7)
    end
    base = day_number(year, month, spec.day)
    spec.kind == :after && return base + mod(spec.weekday - weekday_of(base), 7)
    spec.kind == :before && return base - mod(weekday_of(base) - spec.weekday, 7)
    base
end
