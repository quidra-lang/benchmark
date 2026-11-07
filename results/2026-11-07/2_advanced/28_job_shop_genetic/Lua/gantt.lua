local M = {}
function M.chart_scale(makespan, width)
    local magnitude = 1
    while true do
        for _, step in ipairs({1, 2, 5}) do
            local scale = step * magnitude
            local columns = (makespan + scale - 1) // scale
            if columns <= width then
                return scale, columns
            end
        end
        magnitude = magnitude * 10
    end
end
function M.time_row(scale, columns)
    local row = "time"
    for column = 0, columns - 1, 10 do
        row = row .. string.rep(" ", math.max(0, 6 + column - #row)) .. column * scale
    end
    return row
end
function M.rule_row(columns)
    local marks = {}
    for column = 0, columns - 1 do
        marks[#marks + 1] = column % 10 == 0 and "+" or "-"
    end
    return "      " .. table.concat(marks)
end
local function framed(label, marks)
    return label .. string.rep(" ", math.max(0, 4 - #label)) .. " |" .. marks .. "|"
end
function M.chart_row(label, intervals, scale, columns)
    local ordered = {table.unpack(intervals)}
    table.sort(ordered, function(a, b)
        return a.start < b.start
    end)
    local marks = {}
    for column = 0, columns - 1 do
        local widest, mark = 0, "."
        for _, interval in ipairs(ordered) do
            local overlap = math.min(interval.finish, (column + 1) * scale) - math.max(interval.start, column * scale)
            if overlap > widest then
                widest, mark = overlap, interval.mark
            end
        end
        marks[#marks + 1] = mark
    end
    return framed(label, table.concat(marks))
end
function M.busy_row(machine_intervals, scale, columns)
    local marks = {}
    for column = 0, columns - 1 do
        local time, busy = column * scale, 0
        for _, intervals in ipairs(machine_intervals) do
            for _, interval in ipairs(intervals) do
                if interval.start <= time and time < interval.finish then
                    busy = busy + 1
                    break
                end
            end
        end
        marks[#marks + 1] = busy == 10 and "X" or tostring(busy)
    end
    return framed("busy", table.concat(marks))
end
return M
