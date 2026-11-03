local headers = require("headers")
local M = {}
local weekdays = {mon = 0, tue = 1, wed = 2, thu = 3, fri = 4, sat = 5, sun = 6}
local months = {jan = 1, feb = 2, mar = 3, apr = 4, may = 5, jun = 6, jul = 7, aug = 8, sep = 9, oct = 10, nov = 11, dec = 12}
local month_days = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
local zones = {ut = 0, gmt = 0, z = 0, est = -300, edt = -240, cst = -360, cdt = -300, mst = -420, mdt = -360, pst = -480, pdt = -420}

local function leap(year) return year % 4 == 0 and year % 100 ~= 0 or year % 400 == 0 end
local function days_in_year(year) return leap(year) and 366 or 365 end
local function days_in_month(year, month) return month == 2 and leap(year) and 29 or month_days[month] end
local function digits(text, first, second)
    return (#text == first or second ~= nil and #text == second) and text:match("^%d+$") ~= nil
end

function M.parse_date(value)
    local text = headers.remove_comments(value)
    if text == nil then return nil, "bad Date syntax" end
    local tokens = headers.split_words((text:gsub(",", " , ")))
    local weekday
    if #tokens >= 3 and weekdays[tokens[1]:lower()] ~= nil and tokens[2] == "," then
        weekday = weekdays[tokens[1]:lower()]
        table.remove(tokens, 1)
        table.remove(tokens, 1)
    end
    if #tokens ~= 5 then return nil, "bad Date syntax" end
    local day_text, month_text, year_text, time_text, zone_text = table.unpack(tokens)
    local pieces = headers.split(time_text, ":")
    local numeric_zone = zone_text:match("^[+-]%d%d%d%d$") ~= nil
    if not digits(day_text, 1, 2) or months[month_text:lower()] == nil or not digits(year_text, 2, 4)
        or #pieces ~= 2 and #pieces ~= 3 or not numeric_zone and zones[zone_text:lower()] == nil then return nil, "bad Date syntax" end
    for _, piece in ipairs(pieces) do if not digits(piece, 2) then return nil, "bad Date syntax" end end
    local day, month, year = tonumber(day_text), months[month_text:lower()], tonumber(year_text)
    if #year_text == 2 then year = year + (year < 50 and 2000 or 1900) end
    local hour, minute, second = tonumber(pieces[1]), tonumber(pieces[2]), tonumber(pieces[3]) or 0
    local offset
    if numeric_zone then
        local zone_hour, zone_minute = tonumber(zone_text:sub(2, 3)), tonumber(zone_text:sub(4, 5))
        if zone_hour > 23 or zone_minute > 59 then return nil, "Date out of range" end
        offset = (zone_hour * 60 + zone_minute) * (zone_text:sub(1, 1) == "-" and -1 or 1)
    else offset = zones[zone_text:lower()] end
    if year < 1970 or year > 2099 or day < 1 or day > days_in_month(year, month) or hour > 23 or minute > 59 or second > 59 then return nil, "Date out of range" end
    local days = day - 1
    for current = 1970, year - 1 do days = days + days_in_year(current) end
    for current = 1, month - 1 do days = days + days_in_month(year, current) end
    local seconds = days * 86400 + hour * 3600 + minute * 60 + second - offset * 60
    if seconds < 0 then return nil, "Date out of range" end
    if weekday ~= nil and (days + 3) % 7 ~= weekday then return nil, "Date weekday mismatch" end
    return seconds
end

function M.format_utc(seconds)
    local days, rest, year, month = seconds // 86400, seconds % 86400, 1970, 1
    while days >= days_in_year(year) do days, year = days - days_in_year(year), year + 1 end
    while days >= days_in_month(year, month) do days, month = days - days_in_month(year, month), month + 1 end
    local hour, minute, second = rest // 3600, rest % 3600 // 60, rest % 60
    return string.format("%04d-%02d-%02d %02d:%02d:%02d", year, month, days + 1, hour, minute, second)
end

return M
