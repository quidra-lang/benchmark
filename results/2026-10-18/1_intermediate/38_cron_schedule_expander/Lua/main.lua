local weekdays = {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"}
local months = {"January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"}
local monthDays = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
local function fail(message) error({command_error = true, message = message}, 0) end
local function digits(text, minimum, maximum)
    return #text >= minimum and #text <= maximum and text:match("^[0-9]+$") ~= nil
end
local function words(text)
    local result = {}
    for word in text:gmatch("[^ ]+") do result[#result + 1] = word end
    return result
end
local function split(text, delimiter)
    local result, start = {}, 1
    while true do
        local position = text:find(delimiter, start, true)
        if not position then result[#result + 1] = text:sub(start); return result end
        result[#result + 1] = text:sub(start, position - 1)
        start = position + #delimiter
    end
end
local function tail(values, start)
    local result = {}
    for i = start, #values do result[#result + 1] = values[i] end
    return result
end
local function sortedKeys(values)
    local result = {}
    for key in pairs(values) do result[#result + 1] = key end
    table.sort(result)
    return result
end
local function asciiLess(a, b)
    for i = 1, math.min(#a, #b) do
        if a:byte(i) ~= b:byte(i) then return a:byte(i) < b:byte(i) end
    end
    return #a < #b
end
local function leap(year) return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0) end
local function monthLength(year, month) return month == 2 and leap(year) and 29 or monthDays[month] end

local CivilDate = {}
CivilDate.__index = CivilDate
function CivilDate.new(year, month, day)
    local number = day - 1
    for y = 2000, year - 1 do number = number + (leap(y) and 366 or 365) end
    for m = 1, month - 1 do number = number + monthLength(year, m) end
    return setmetatable({year = year, month = month, day = day, number = number, weekday = (number + 6) % 7}, CivilDate)
end
function CivilDate.fromNumber(number)
    local rest, year, month = number, 2000, 1
    while rest >= (leap(year) and 366 or 365) do rest = rest - (leap(year) and 366 or 365); year = year + 1 end
    while rest >= monthLength(year, month) do rest = rest - monthLength(year, month); month = month + 1 end
    return setmetatable({year = year, month = month, day = rest + 1, number = number, weekday = (number + 6) % 7}, CivilDate)
end
function CivilDate.parse(text)
    if #text ~= 10 or text:sub(5, 5) ~= "-" or text:sub(8, 8) ~= "-" or not digits(text:sub(1, 4), 4, 4)
        or not digits(text:sub(6, 7), 2, 2) or not digits(text:sub(9), 2, 2) then return nil end
    local year, month, day = tonumber(text:sub(1, 4), 10), tonumber(text:sub(6, 7), 10), tonumber(text:sub(9), 10)
    if year < 2001 or year > 2098 or month < 1 or month > 12 or day < 1 or day > monthLength(year, month) then return nil end
    return CivilDate.new(year, month, day)
end
function CivilDate:dateText() return string.format("%04d-%02d-%02d", self.year, self.month, self.day) end
function CivilDate:__tostring() return self:dateText() .. " " .. weekdays[self.weekday + 1]:sub(1, 3) end
local function readDate(text) return CivilDate.parse(text) or fail("invalid date") end
local function readMinute(dateText, time)
    local date = CivilDate.parse(dateText)
    if not date or #time ~= 5 or time:sub(3, 3) ~= ":" or not digits(time:sub(1, 2), 2, 2) or not digits(time:sub(4), 2, 2) then fail("invalid datetime") end
    local hour, minute = tonumber(time:sub(1, 2), 10), tonumber(time:sub(4), 10)
    if hour > 23 or minute > 59 then fail("invalid datetime") end
    return date.number * 1440 + hour * 60 + minute
end
local function readMonth(text)
    if #text ~= 7 or text:sub(5, 5) ~= "-" or not digits(text:sub(1, 4), 4, 4) or not digits(text:sub(6), 2, 2) then fail("invalid month") end
    local year, month = tonumber(text:sub(1, 4), 10), tonumber(text:sub(6), 10)
    if year < 2001 or year > 2098 or month < 1 or month > 12 then fail("invalid month") end
    return year, month
end
local function minuteText(minute)
    local date = CivilDate.fromNumber(minute // 1440)
    return date:dateText() .. string.format(" %02d:%02d ", minute % 1440 // 60, minute % 60) .. weekdays[date.weekday + 1]:sub(1, 3)
end
local function span(minutes) return string.format("%dd%02dh%02dm", minutes // 1440, minutes % 1440 // 60, minutes % 60) end
local function checkWindow(low, high)
    if low > high then fail("invalid window") end
    if high - low > 44640 then fail("window too long") end
end

local fieldNames = {"minute", "hour", "day-of-month", "month", "day-of-week"}
local minimum, maximum = {0, 0, 1, 1, 0}, {59, 23, 31, 12, 7}
local monthCodes = {JAN = 1, FEB = 2, MAR = 3, APR = 4, MAY = 5, JUN = 6, JUL = 7, AUG = 8, SEP = 9, OCT = 10, NOV = 11, DEC = 12}
local dayCodes = {SUN = 0, MON = 1, TUE = 2, WED = 3, THU = 4, FRI = 5, SAT = 6}
local macros = {
    ["@yearly"] = "0 0 1 1 *", ["@annually"] = "0 0 1 1 *", ["@monthly"] = "0 0 1 * *", ["@weekly"] = "0 0 * * 0",
    ["@daily"] = "0 0 * * *", ["@midnight"] = "0 0 * * *", ["@hourly"] = "0 * * * *",
}
local function fieldError(index, reason) fail(fieldNames[index] .. " " .. reason) end
local function readValue(text, index)
    local named = index == 4 and monthCodes[text] or index == 5 and dayCodes[text] or nil
    if named ~= nil then return named end
    if not digits(text, 1, 2) then fieldError(index, "invalid value") end
    local value = tonumber(text, 10)
    if value < minimum[index] or value > maximum[index] then fieldError(index, "out of range") end
    return value
end
local function specialNumber(text, index, upper, size)
    if not digits(text, 1, size or 2) then fieldError(index, "invalid value") end
    local value = tonumber(text, 10)
    if value < 1 or value > upper then fieldError(index, "out of range") end
    return value
end
local Special = {}
Special.__index = Special
function Special.new(kind, value, occurrence) return setmetatable({kind = kind, value = value or 0, occurrence = occurrence or 0}, Special) end
function Special:__tostring()
    if self.kind == "last" then return "L"
    elseif self.kind == "lastWeekday" then return "LW"
    elseif self.kind == "beforeLast" then return "L-" .. self.value
    elseif self.kind == "nearestWeekday" then return self.value .. "W"
    elseif self.kind == "nthWeekday" then return self.value .. "#" .. self.occurrence
    else return self.value .. "L" end
end
local function readField(text, index)
    local values, specials, seen = {}, {}, {}
    for _, item in ipairs(split(text, ",")) do
        if item == "" then fieldError(index, "empty item") end
        local special, hash = nil, item:find("#", 1, true)
        if index == 3 and (item:sub(1, 1) == "L" or item:sub(-1) == "W") then
            if item == "L" then special = Special.new("last")
            elseif item == "LW" then special = Special.new("lastWeekday")
            elseif item:sub(1, 2) == "L-" then special = Special.new("beforeLast", specialNumber(item:sub(3), index, 30))
            elseif item:sub(-1) == "W" then special = Special.new("nearestWeekday", specialNumber(item:sub(1, -2), index, 31))
            else fieldError(index, "invalid value") end
        elseif index == 5 and hash then
            local weekday = readValue(item:sub(1, hash - 1), index)
            local occurrence = specialNumber(item:sub(hash + 1), index, 5, 1)
            special = Special.new("nthWeekday", weekday % 7, occurrence)
        elseif index == 5 and #item >= 2 and item:sub(-1) == "L" then
            special = Special.new("lastOccurrence", readValue(item:sub(1, -2), index) % 7)
        end
        if special then
            local canonical = tostring(special)
            if not seen[canonical] then seen[canonical] = true; specials[#specials + 1] = special end
        else
            local slash = item:find("/", 1, true)
            local base = slash and item:sub(1, slash - 1) or item
            local low, high, dash = nil, nil, base:find("-", 1, true)
            if base == "*" then low, high = minimum[index], maximum[index]
            elseif dash then
                low = readValue(base:sub(1, dash - 1), index)
                high = readValue(base:sub(dash + 1), index)
                if low > high then fieldError(index, "invalid range") end
            else low = readValue(base, index); high = slash and maximum[index] or low end
            local step = 1
            if slash then
                local part = item:sub(slash + 1)
                if not digits(part, 1, 2) or tonumber(part, 10) == 0 then fieldError(index, "invalid step") end
                step = tonumber(part, 10)
            end
            for value = low, high, step do values[index == 5 and value % 7 or value] = true end
        end
    end
    return {index = index, values = sortedKeys(values), set = values, specials = specials, restricted = text:sub(1, 1) ~= "*"}
end

local Cron = {}
Cron.__index = Cron
function Cron.parse(input)
    if #input == 1 and input[1]:sub(1, 1) == "@" then input = words(macros[input[1]] or fail("unknown macro")) end
    if #input ~= 5 then fail("field count") end
    local fields, daily = {}, {}
    for i = 1, 5 do fields[i] = readField(input[i], i) end
    for _, hour in ipairs(fields[2].values) do
        for _, minute in ipairs(fields[1].values) do daily[#daily + 1] = hour * 60 + minute end
    end
    return setmetatable({fields = fields, daily = daily, expanded = table.concat(input, " ")}, Cron)
end
function Cron:orRule() return self.fields[3].restricted and self.fields[5].restricted end
function Cron:rule() return self:orRule() and "OR" or "AND" end
local function nearest(date, day)
    local weekday = (date.number - date.day + day + 6) % 7
    if weekday == 6 then return day == 1 and 3 or day - 1 end
    if weekday == 0 then return day == monthLength(date.year, date.month) and day - 2 or day + 1 end
    return day
end
function Cron:matchDay(date)
    local last, day, weekday = monthLength(date.year, date.month), date.day, date.weekday
    local monthDay, weekDay = self.fields[3].set[day] == true, self.fields[5].set[weekday] == true
    for _, special in ipairs(self.fields[3].specials) do
        local matches
        if special.kind == "last" then matches = day == last
        elseif special.kind == "lastWeekday" then matches = day == nearest(date, last)
        elseif special.kind == "beforeLast" then matches = day == last - special.value
        else matches = special.value <= last and day == nearest(date, special.value) end
        monthDay = monthDay or matches
    end
    for _, special in ipairs(self.fields[5].specials) do
        local matches
        if special.kind == "nthWeekday" then matches = weekday == special.value and (day - 1) // 7 + 1 == special.occurrence
        else matches = weekday == special.value and day + 7 > last end
        weekDay = weekDay or matches
    end
    local condition
    if self:orRule() then condition = monthDay or weekDay else condition = monthDay and weekDay end
    return monthDay, weekDay, condition
end
function Cron:scheduled(date)
    local _, _, condition = self:matchDay(date)
    return self.fields[4].set[date.month] == true and condition
end
function Cron:fireTimes(low, high, holidays, reverse)
    return coroutine.wrap(function()
        local first, last = low // 1440, high // 1440
        local step = reverse and -1 or 1
        for day = reverse and last or first, reverse and first or last, step do
            if not holidays[day] and self:scheduled(CivilDate.fromNumber(day)) then
                for i = reverse and #self.daily or 1, reverse and 1 or #self.daily, step do
                    local time = day * 1440 + self.daily[i]
                    if low <= time and time <= high then coroutine.yield(time) end
                end
            end
        end
    end)
end
function Cron:reasons(time, holidays)
    local date, result = CivilDate.fromNumber(time // 1440), {}
    local monthDay, weekDay, condition = self:matchDay(date)
    if not self.fields[1].set[time % 60] then result[#result + 1] = "minute" end
    if not self.fields[2].set[time % 1440 // 60] then result[#result + 1] = "hour" end
    if not condition and not monthDay then result[#result + 1] = "day-of-month" end
    if not self.fields[4].set[date.month] then result[#result + 1] = "month" end
    if not condition and not weekDay then result[#result + 1] = "day-of-week" end
    if holidays[date.number] then result[#result + 1] = "excluded" end
    return result
end
local function listJoin(parts, either)
    if #parts < 2 then return parts[1] or "" end
    return table.concat(parts, ", ", 1, #parts - 1) .. (either and " or " or " and ") .. parts[#parts]
end
local function valueName(index, value)
    if index == 4 then return months[value] end
    if index == 5 then return weekdays[value + 1] end
    return tostring(value)
end
local function valueList(field, either)
    local parts, values, start = {}, field.values, 1
    while start <= #values do
        local finish = start
        while finish < #values and values[finish + 1] == values[finish] + 1 do finish = finish + 1 end
        if finish - start >= 2 then parts[#parts + 1] = valueName(field.index, values[start]) .. " through " .. valueName(field.index, values[finish])
        else for i = start, finish do parts[#parts + 1] = valueName(field.index, values[i]) end end
        start = finish + 1
    end
    return listJoin(parts, either)
end
local function stepped(field)
    local values = field.values
    if #values < 2 or values[1] ~= 0 or values[2] < 2 then return 0 end
    local step = values[2]
    if #values ~= maximum[field.index] // step + 1 then return 0 end
    for i, value in ipairs(values) do if value ~= (i - 1) * step then return 0 end end
    return step
end
function Cron:dayClause(weekday, either)
    local field, parts = self.fields[weekday and 5 or 3], {}
    if #field.values > 0 then
        parts[#parts + 1] = weekday and valueList(field, either) or ((#field.values == 1 and "day " or "days ") .. valueList(field))
    end
    local ordinals = {"1st", "2nd", "3rd", "4th", "5th"}
    for _, special in ipairs(field.specials) do
        local part
        if special.kind == "last" then part = "the last day"
        elseif special.kind == "lastWeekday" then part = "the last weekday"
        elseif special.kind == "beforeLast" then part = special.value .. (special.value == 1 and " day" or " days") .. " before the last day"
        elseif special.kind == "nearestWeekday" then part = "the weekday nearest day " .. special.value
        elseif special.kind == "nthWeekday" then part = "the " .. ordinals[special.occurrence] .. " " .. weekdays[special.value + 1]
        else part = "the last " .. weekdays[special.value + 1] end
        parts[#parts + 1] = part
    end
    return listJoin(parts, either) .. ((not weekday or #field.specials > 0) and " of the month" or "")
end
function Cron:describe()
    local minute, hour, text = self.fields[1], self.fields[2], nil
    if #self.daily <= 4 then
        local times = {}
        for _, time in ipairs(self.daily) do times[#times + 1] = string.format("%02d:%02d", time // 60, time % 60) end
        text = "At " .. listJoin(times)
    else
        local minuteStep, hourStep = stepped(minute), stepped(hour)
        if #minute.values == 60 then text = "Every minute"
        elseif minuteStep ~= 0 then text = "Every " .. minuteStep .. " minutes"
        elseif #minute.values == 1 then text = "At minute " .. minute.values[1]
        else text = "At minutes " .. valueList(minute) end
        if #hour.values == 24 then
            if text:sub(1, 9) == "At minute" then text = text .. " of every hour" end
        elseif hourStep ~= 0 then text = text .. ", every " .. hourStep .. " hours"
        elseif hour.values[#hour.values] - hour.values[1] + 1 == #hour.values then text = text .. string.format(", between %02d:00 and %02d:59", hour.values[1], hour.values[#hour.values])
        else text = text .. ", during hours " .. valueList(hour) end
    end
    local monthFull, weekFull = #self.fields[3].values == 31, #self.fields[5].values == 7
    if self:orRule() then
        if not monthFull and not weekFull then text = text .. ", on " .. self:dayClause(false) .. " or on " .. self:dayClause(true) end
    elseif not monthFull and not weekFull then text = text .. ", on " .. self:dayClause(false) .. " if it is " .. self:dayClause(true, true)
    elseif not monthFull then text = text .. ", on " .. self:dayClause(false)
    elseif not weekFull then text = text .. ", on " .. self:dayClause(true) end
    if #self.fields[4].values ~= 12 then text = text .. ", in " .. valueList(self.fields[4]) end
    return text
end

local arity = {
    JOB = -2, VALIDATE = -1, REMOVE = 1, RENAME = 2, ENABLE = 1, DISABLE = 1, RUNTIME = 3, LIST = 0,
    EXPAND = 2, DESCRIBE = 1, MATCH = 3, NEXT = 4, PREV = 4, COUNT = 5, GAP = 3, OVERLAP = 6,
    TIMELINE = 4, CONFLICTS = 4, WEEK = 1, CALENDAR = 2, SIMULATE = 4, EXCLUDE = 1, INCLUDE = 1, HOLIDAYS = 0,
}
local Scheduler = {}
Scheduler.__index = Scheduler
function Scheduler.new() return setmetatable({jobs = {}, holidays = {}, holidayCount = 0}, Scheduler) end
function Scheduler:getJob(id) return self.jobs[id] or fail("unknown job") end
function Scheduler:newId(id)
    if #id < 1 or #id > 16 or not id:match("^[a-z][a-z0-9_]*$") then fail("invalid id") end
    if self.jobs[id] then fail("duplicate job") end
end
local function positive(text, size, upper, reason)
    if not digits(text, 1, size) or text:sub(1, 1) == "0" or tonumber(text, 10) > upper then fail(reason) end
    return tonumber(text, 10)
end
function Scheduler:ordered(enabledOnly)
    local result = {}
    for _, job in pairs(self.jobs) do if not enabledOnly or job.enabled then result[#result + 1] = job end end
    table.sort(result, function(a, b) return asciiLess(a.id, b.id) end)
    return result
end
function Scheduler:timeline(low, high, conflicts)
    local schedule = {}
    for _, job in ipairs(self:ordered(true)) do
        for time in job.cron:fireTimes(low, high, self.holidays) do
            schedule[time] = schedule[time] or {}
            schedule[time][#schedule[time] + 1] = job.id
        end
    end
    local times, count, peak = sortedKeys(schedule), 0, 0
    for _, time in ipairs(times) do
        local size = #schedule[time]
        if conflicts then if size >= 2 then count = count + 1; peak = math.max(peak, size) end
        else count = count + size end
    end
    local rows = {conflicts and ("CONFLICTS " .. count .. " peak " .. peak) or ("TIMELINE " .. count)}
    local written = 0
    for _, time in ipairs(times) do
        if written == 100 then break end
        local ids = schedule[time]
        if conflicts then
            if #ids >= 2 then rows[#rows + 1] = minuteText(time) .. " " .. #ids .. " " .. table.concat(ids, " "); written = written + 1 end
        else
            for _, id in ipairs(ids) do
                if written == 100 then break end
                rows[#rows + 1] = minuteText(time) .. " " .. id; written = written + 1
            end
        end
    end
    if count > 100 then rows[#rows + 1] = "... " .. (count - 100) .. " more" end
    return rows
end
function Scheduler:week(input, start)
    local counts, total, low = {}, 0, start.number * 1440
    for day = 1, 7 do counts[day] = {}; for hour = 1, 24 do counts[day][hour] = 0 end end
    for _, job in ipairs(self:ordered(true)) do
        for time in job.cron:fireTimes(low, low + 7 * 1440 - 1, self.holidays) do
            local day, hour = (time - low) // 1440 + 1, time % 1440 // 60 + 1
            counts[day][hour] = counts[day][hour] + 1; total = total + 1
        end
    end
    local rows = {"WEEK " .. input .. " " .. total}
    for day = 1, 7 do
        local marks, subtotal = {}, 0
        for _, count in ipairs(counts[day]) do
            subtotal = subtotal + count
            marks[#marks + 1] = count == 0 and "." or count >= 10 and "+" or tostring(count)
        end
        rows[#rows + 1] = tostring(CivilDate.fromNumber(start.number + day - 1)) .. " " .. table.concat(marks) .. " " .. subtotal
    end
    return rows
end
function Scheduler:calendar(job, input, year, month)
    local first, cells, count = CivilDate.new(year, month, 1), {}, 0
    for _ = 1, first.weekday do cells[#cells + 1] = "..." end
    for day = 1, monthLength(year, month) do
        local date = CivilDate.new(year, month, day)
        local mark = job.cron:scheduled(date) and (self.holidays[date.number] and "x" or "*") or "-"
        if mark == "*" then count = count + 1 end
        cells[#cells + 1] = string.format("%02d%s", day, mark)
    end
    while #cells % 7 ~= 0 do cells[#cells + 1] = "..." end
    local rows = {"CALENDAR " .. job.id .. " " .. input .. " days " .. count .. " runs " .. count * #job.cron.daily, "Sun Mon Tue Wed Thu Fri Sat"}
    for i = 1, #cells, 7 do rows[#rows + 1] = table.concat(cells, " ", i, i + 6) end
    return rows
end
function Scheduler:simulate(low, high)
    local jobs, events, details = self:ordered(true), {}, {}
    for _, job in ipairs(jobs) do
        local started, skipped, replaced, busy, lastEnd = 0, 0, 0, 0, 0
        for time in job.cron:fireTimes(low, high, self.holidays) do
            if lastEnd > time and job.policy == "FORBID" then skipped = skipped + 1
            else
                if lastEnd > time and job.policy == "REPLACE" then
                    events[lastEnd] = (events[lastEnd] or 0) + 1
                    events[time] = (events[time] or 0) - 1
                    busy = busy - (lastEnd - time); replaced = replaced + 1
                end
                lastEnd = time + job.duration
                events[time] = (events[time] or 0) + 1
                events[lastEnd] = (events[lastEnd] or 0) - 1
                started = started + 1; busy = busy + job.duration
            end
        end
        details[#details + 1] = job.id .. " " .. job.policy .. " started " .. started .. " skipped " .. skipped .. " replaced " .. replaced .. " busy " .. busy
    end
    local running, peak, at = 0, 0, 0
    for _, time in ipairs(sortedKeys(events)) do
        running = running + events[time]
        if running > peak then peak, at = running, time end
    end
    local rows = {"SIMULATE " .. #jobs .. " peak " .. peak .. (peak == 0 and "" or " at " .. minuteText(at))}
    for _, detail in ipairs(details) do rows[#rows + 1] = detail end
    return rows
end
function Scheduler:execute(tokens)
    local command, expected = tokens[1], arity[tokens[1]]
    if expected == nil then fail("unknown command") end
    local count = #tokens - 1
    if expected < 0 and count < -expected or expected >= 0 and count ~= expected then fail("wrong arguments") end
    if command == "JOB" then
        local id = tokens[2]; self:newId(id)
        local expression = tail(tokens, 3); local cron = Cron.parse(expression)
        self.jobs[id] = {id = id, cron = cron, text = table.concat(expression, " "), enabled = true, duration = 1, policy = "ALLOW"}
        return {"JOB " .. id .. " added"}
    elseif command == "VALIDATE" then
        local cron = Cron.parse(tail(tokens, 2))
        return {"VALID " .. cron.expanded .. " " .. cron:rule() .. " " .. #cron.daily}
    elseif command == "REMOVE" then
        local job = self:getJob(tokens[2]); self.jobs[job.id] = nil
        return {"REMOVE " .. job.id}
    elseif command == "RENAME" then
        local job = self:getJob(tokens[2]); self:newId(tokens[3])
        self.jobs[job.id] = nil; job.id = tokens[3]; self.jobs[job.id] = job
        return {"RENAME " .. tokens[2] .. " " .. job.id}
    elseif command == "ENABLE" or command == "DISABLE" then
        local job, enable = self:getJob(tokens[2]), command == "ENABLE"
        if job.enabled == enable then fail(enable and "already enabled" or "already disabled") end
        job.enabled = enable
        return {command .. " " .. job.id}
    elseif command == "RUNTIME" then
        local job = self:getJob(tokens[2]); local duration = positive(tokens[3], 4, 1440, "invalid duration")
        local policy = tokens[4]
        if policy ~= "ALLOW" and policy ~= "FORBID" and policy ~= "REPLACE" then fail("invalid policy") end
        job.duration, job.policy = duration, policy
        return {"RUNTIME " .. job.id .. " " .. duration .. " " .. policy}
    elseif command == "LIST" then
        local jobs = self:ordered(); local rows = {"LIST " .. #jobs}
        for _, job in ipairs(jobs) do rows[#rows + 1] = job.id .. (job.enabled and " on " or " off ") .. job.duration .. " " .. job.policy .. " " .. job.text end
        return rows
    elseif command == "EXPAND" then
        local job = self:getJob(tokens[2]); local index
        for i, name in ipairs(fieldNames) do if name == tokens[3] then index = i; break end end
        if not index then fail("invalid field") end
        local field, items = job.cron.fields[index], {}
        for _, value in ipairs(field.values) do items[#items + 1] = tostring(value) end
        for _, special in ipairs(field.specials) do items[#items + 1] = tostring(special) end
        return {"EXPAND " .. job.id .. " " .. tokens[3] .. " " .. #field.values .. (#items == 0 and "" or " " .. table.concat(items, " "))}
    elseif command == "DESCRIBE" then
        local job = self:getJob(tokens[2]); return {"DESCRIBE " .. job.id .. " " .. job.cron:describe()}
    elseif command == "MATCH" then
        local job = self:getJob(tokens[2]); local time = readMinute(tokens[3], tokens[4])
        local reasons = job.cron:reasons(time, self.holidays)
        return {"MATCH " .. job.id .. " " .. minuteText(time) .. (#reasons == 0 and " yes" or " no " .. table.concat(reasons, " "))}
    elseif command == "NEXT" or command == "PREV" then
        local job = self:getJob(tokens[2]); local start = readMinute(tokens[3], tokens[4])
        local limit = positive(tokens[5], 2, 50, "invalid count"); local reverse, times = command == "PREV", {}
        for time in job.cron:fireTimes(reverse and start - 527040 or start + 1, reverse and start - 1 or start + 527040, self.holidays, reverse) do
            times[#times + 1] = time; if #times == limit then break end
        end
        local rows = {command .. " " .. job.id .. " " .. #times}
        for _, time in ipairs(times) do rows[#rows + 1] = minuteText(time) .. (reverse and " -" or " +") .. span(math.abs(time - start)) end
        if #times < limit then rows[#rows + 1] = "NONE" end
        return rows
    elseif command == "COUNT" then
        local job = self:getJob(tokens[2]); local low = readMinute(tokens[3], tokens[4]); local high = readMinute(tokens[5], tokens[6]); checkWindow(low, high)
        local runs, days = 0, {}
        for time in job.cron:fireTimes(low, high, self.holidays) do runs = runs + 1; days[time // 1440] = true end
        return {"COUNT " .. job.id .. " runs " .. runs .. " days " .. #sortedKeys(days)}
    elseif command == "GAP" then
        local job = self:getJob(tokens[2]); local start = readMinute(tokens[3], tokens[4]); local times = {}
        for time in job.cron:fireTimes(start, start + 44640, self.holidays) do times[#times + 1] = time end
        if #times < 2 then return {"GAP " .. job.id .. " runs " .. #times .. " none"} end
        local frequencies, shortest, longest, from = {}, 44641, 0, 1
        for i = 2, #times do
            local gap = times[i] - times[i - 1]; shortest = math.min(shortest, gap)
            if gap > longest then longest, from = gap, i - 1 end
            frequencies[gap] = (frequencies[gap] or 0) + 1
        end
        local rows = {"GAP " .. job.id .. " runs " .. #times .. " shortest " .. span(shortest) .. " longest " .. span(longest) .. " from " .. minuteText(times[from]) .. " to " .. minuteText(times[from + 1])}
        for _, gap in ipairs(sortedKeys(frequencies)) do rows[#rows + 1] = span(gap) .. " " .. frequencies[gap] end
        return rows
    elseif command == "OVERLAP" then
        local a = self:getJob(tokens[2]); local b = self:getJob(tokens[3])
        local low = readMinute(tokens[4], tokens[5]); local high = readMinute(tokens[6], tokens[7]); checkWindow(low, high)
        local other, times = {}, {}
        for time in b.cron:fireTimes(low, high, self.holidays) do other[time] = true end
        for time in a.cron:fireTimes(low, high, self.holidays) do if other[time] then times[#times + 1] = time end end
        return {"OVERLAP " .. a.id .. " " .. b.id .. " " .. #times .. (#times == 0 and "" or " first " .. minuteText(times[1]) .. " last " .. minuteText(times[#times]))}
    elseif command == "TIMELINE" or command == "CONFLICTS" or command == "SIMULATE" then
        local low = readMinute(tokens[2], tokens[3]); local high = readMinute(tokens[4], tokens[5]); checkWindow(low, high)
        if command == "SIMULATE" then return self:simulate(low, high) end
        return self:timeline(low, high, command == "CONFLICTS")
    elseif command == "WEEK" then
        local date = readDate(tokens[2]); return self:week(tokens[2], date)
    elseif command == "CALENDAR" then
        local job = self:getJob(tokens[2]); local year, month = readMonth(tokens[3])
        return self:calendar(job, tokens[3], year, month)
    elseif command == "EXCLUDE" or command == "INCLUDE" then
        local date = readDate(tokens[2]); local day = date.number
        if command == "EXCLUDE" then
            if self.holidays[day] then fail("already excluded") end
            self.holidays[day] = true; self.holidayCount = self.holidayCount + 1
        else
            if not self.holidays[day] then fail("not excluded") end
            self.holidays[day] = nil; self.holidayCount = self.holidayCount - 1
        end
        return {command .. " " .. tostring(date) .. " holidays " .. self.holidayCount}
    else
        local rows = {"HOLIDAYS " .. self.holidayCount}
        for _, day in ipairs(sortedKeys(self.holidays)) do rows[#rows + 1] = tostring(CivilDate.fromNumber(day)) end
        return rows
    end
end

local first = io.read("*l")
if not first then return end
local scheduler = Scheduler.new()
for _ = 1, tonumber(first, 10) do
    local tokens = words((io.read("*l")):gsub("\r$", ""))
    local ok, result = pcall(scheduler.execute, scheduler, tokens)
    if ok then for _, row in ipairs(result) do io.write(row, "\n") end
    elseif type(result) == "table" and result.command_error then io.write("ERROR ", result.message, "\n")
    else error(result, 0) end
end
