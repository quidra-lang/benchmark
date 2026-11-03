local M = {
    MONTH_NAMES = {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"},
    WEEKDAY_NAMES = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"},
    COMMON_MONTH_DAYS = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31},
    SECONDS_PER_DAY = 86400,
    NEG_INFINITY = -4611686018427387904,
    POS_INFINITY = 4611686018427387904,
}

function M.is_leap_year(year) return year % 4 == 0 and year % 100 ~= 0 or year % 400 == 0 end
function M.days_in_month(year, month) return month == 2 and M.is_leap_year(year) and 29 or M.COMMON_MONTH_DAYS[month] end
local function days_before_year(year)
    local previous = year - 1
    return previous * 365 + previous // 4 - previous // 100 + previous // 400
end
function M.day_number(year, month, day)
    local days = days_before_year(year) - days_before_year(1970) + day - 1
    for earlier = 1, month - 1 do days = days + M.days_in_month(year, earlier) end
    return days
end
function M.weekday_of(number) return (number + 4) % 7 end
function M.date_of_day(number)
    local year = 1970 + number // 366
    while M.day_number(year, 1, 1) > number do year = year - 1 end
    while M.day_number(year + 1, 1, 1) <= number do year = year + 1 end
    local month, day = 1, number - M.day_number(year, 1, 1) + 1
    while day > M.days_in_month(year, month) do day = day - M.days_in_month(year, month) month = month + 1 end
    return year, month, day
end
function M.time_value(year, month, day, hour, minute, second)
    return M.day_number(year, month, day) * 86400 + hour * 3600 + minute * 60 + second
end
function M.split_time(time)
    local year, month, day = M.date_of_day(time // 86400)
    local seconds = time % 86400
    return year, month, day, seconds // 3600, seconds // 60 % 60, seconds % 60
end

local DaySpec = {}
DaySpec.__index = DaySpec
function DaySpec.new(kind, weekday, day) return setmetatable({kind = kind, weekday = weekday, day = day}, DaySpec) end
function DaySpec:value(year, month)
    if self.kind == "last" then
        local last = M.day_number(year, month, M.days_in_month(year, month))
        return last - (M.weekday_of(last) - self.weekday) % 7
    end
    local base = M.day_number(year, month, self.day)
    if self.kind == "after" then return base + (self.weekday - M.weekday_of(base)) % 7 end
    if self.kind == "before" then return base - (M.weekday_of(base) - self.weekday) % 7 end
    return base
end
M.DaySpec = DaySpec
return M
