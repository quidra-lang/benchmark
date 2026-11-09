local report = require('report')
local M = {}
local months = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
function M.read()
    local rows, parameters = {}, {}
    local line_number = 0
    for line in io.lines('input/eventlog.csv') do
        line_number = line_number + 1
        if line_number > 1 then
            local id, activity, timestamp, resource = line:match('^([^,]+),([^,]+),([^,]+),([^,]+)$')
            rows[#rows + 1] = {line = line_number, id = id, activity = activity, timestamp = timestamp, resource = resource}
        end
    end
    for line in io.lines('input/params.txt') do local k, v = line:match('^(%S+) (%S+)$'); parameters[k] = v end
    return rows, parameters
end
function M.minutes(timestamp)
    local m, d = tonumber(timestamp:sub(6, 7)), tonumber(timestamp:sub(9, 10))
    local h, n = tonumber(timestamp:sub(12, 13)), tonumber(timestamp:sub(15, 16))
    if m < 1 or m > 12 or d < 1 or d > months[m] or h > 23 or n > 59 then return nil end
    local days = d - 1
    for i = 1, m - 1 do days = days + months[i] end
    return (days * 24 + h) * 60 + n
end
function M.cases(events)
    local grouped, ids, out = {}, {}, {}
    for _, event in ipairs(events) do
        if not grouped[event.id] then grouped[event.id] = {}; ids[#ids + 1] = event.id end
        local group = grouped[event.id]; group[#group + 1] = event
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local es = grouped[id]
        table.sort(es, function(a, b) return a.time < b.time or (a.time == b.time and a.line < b.line) end)
        local trace = {}; for i, e in ipairs(es) do trace[i] = e.activity end
        out[#out + 1] = {id = id, events = es, trace = trace, duration = es[#es].time - es[1].time}
    end
    return out
end
function M.median(values)
    local a = {}; for i, v in ipairs(values) do a[i] = v end; table.sort(a)
    if #a % 2 == 1 then return report.rational(a[(#a + 1) // 2]) end
    return report.rational(a[#a // 2] + a[#a // 2 + 1], 2)
end
return M
