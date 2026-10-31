local day_rules = require("day_rules")
local M = {MIN_YEAR = 1800, MAX_YEAR = 2099}
function M.field_error(message) error({field_error = message}, 0) end
function M.line_content(raw)
    local comment = raw:find("#", 1, true)
    return (comment and raw:sub(1, comment - 1) or raw):gsub(" +$", "")
end
function M.is_continuation(content) return content:sub(1, 1) == " " end
function M.split_fields(content)
    local fields = {}
    for field in content:gmatch("[^ ]+") do fields[#fields + 1] = field end
    return fields
end
local function is_number(text, minimum, maximum)
    return #text >= minimum and #text <= maximum and text:match("^[0-9]+$") ~= nil
end
function M.hms_value(text, max_parts)
    local parts, start = {}, 1
    while true do
        local separator = text:find(":", start, true)
        parts[#parts + 1] = separator and text:sub(start, separator - 1) or text:sub(start)
        if not separator then break end
        start = separator + 1
    end
    if #parts > (max_parts or 3) or not is_number(parts[1], 1, 2) then return nil end
    local value = tonumber(parts[1]) * 3600
    for index = 2, #parts do
        if not is_number(parts[index], 2, 2) or tonumber(parts[index]) > 59 then return nil end
        value = value + tonumber(parts[index]) * (index == 2 and 60 or 1)
    end
    return value
end
function M.parse_year(text)
    if not is_number(text, 4, 4) or tonumber(text) < 1800 or tonumber(text) > 2099 then M.field_error("bad year") end
    return tonumber(text)
end
function M.parse_to(text, from_year)
    if text == "only" then return from_year end
    if text == "max" then return 2099 end
    if not is_number(text, 4, 4) or tonumber(text) < from_year or tonumber(text) > 2099 then M.field_error("bad year") end
    return tonumber(text)
end
function M.parse_month(text)
    for month, name in ipairs(day_rules.MONTH_NAMES) do if name == text then return month end end
    M.field_error("bad month")
end
local function parse_weekday(text)
    for index, name in ipairs(day_rules.WEEKDAY_NAMES) do if name == text then return index - 1 end end
    M.field_error("bad day spec")
end
local function parse_day_of_month(text, month)
    if not is_number(text, 1, 2) or text:sub(1, 1) == "0" or tonumber(text) > day_rules.COMMON_MONTH_DAYS[month] then M.field_error("bad day spec") end
    return tonumber(text)
end
function M.parse_day_spec(text, month)
    if text:sub(1, 4) == "last" then return day_rules.DaySpec.new("last", parse_weekday(text:sub(5)), 0) end
    for _, item in ipairs({{">=", "after"}, {"<=", "before"}}) do
        local position = text:find(item[1], 1, true)
        if position then
            local weekday = parse_weekday(text:sub(1, position - 1))
            local day = parse_day_of_month(text:sub(position + 2), month)
            return day_rules.DaySpec.new(item[2], weekday, day)
        end
    end
    return day_rules.DaySpec.new("day", 0, parse_day_of_month(text, month))
end
function M.parse_time(text)
    local time_type = "w"
    local suffix = text:sub(-1)
    if suffix == "w" or suffix == "s" or suffix == "u" then time_type, text = suffix, text:sub(1, -2) end
    local value = M.hms_value(text)
    if value == nil or value > 86400 then M.field_error("bad time") end
    return value, time_type
end
function M.parse_save(text)
    local value = M.hms_value(text, 2)
    if value == nil or value > 7200 then M.field_error("bad save") end
    return value
end
function M.parse_letter(text)
    if text == "-" then return "" end
    if #text > 5 or text:match("^[A-Z]+$") == nil then M.field_error("bad letter") end
    return text
end
function M.parse_stdoff(text)
    local sign = 1
    if text:sub(1, 1) == "-" then sign, text = -1, text:sub(2) end
    local value = M.hms_value(text)
    if value == nil or value >= 57600 then M.field_error("bad offset") end
    return sign * value
end
function M.check_format(text, uses_rule_set)
    local _, placeholders = text:gsub("%%s", "")
    local _, percents = text:gsub("%%", "")
    local _, slashes = text:gsub("/", "")
    local valid = text:match("^[a-zA-Z0-9+%%/-]+$") ~= nil and placeholders == percents and placeholders <= 1 and slashes <= 1
        and not (placeholders > 0 and slashes > 0) and (uses_rule_set or placeholders == 0)
    if slashes == 1 then valid = valid and text:sub(1, 1) ~= "/" and text:sub(-1) ~= "/" end
    if not valid then M.field_error("bad format") end
end
function M.parse_until(fields)
    local year = M.parse_year(fields[1])
    local month_text = fields[2] or "Jan"
    local month = M.parse_month(month_text)
    local day_text = fields[3] or "1"
    local day = M.parse_day_spec(day_text, month)
    local time, time_type = 0, "w"
    if fields[4] then time, time_type = M.parse_time(fields[4]) end
    return {year_text = fields[1], month_text = month_text, day_text = day_text, time = time, time_type = time_type, value = day:value(year, month) * 86400 + time}
end
return M
