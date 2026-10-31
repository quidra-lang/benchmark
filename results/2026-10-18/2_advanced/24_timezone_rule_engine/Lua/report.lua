local day_rules = require("day_rules")
local M = {}
function M.local_text(time) return string.format("%04d-%02d-%02dT%02d:%02d:%02d", day_rules.split_time(time)) end
function M.ut_text(time) return M.local_text(time) .. "Z" end
function M.offset_text(value)
    local sign = value < 0 and "-" or "+"
    value = math.abs(value)
    local text = string.format("%s%02d:%02d", sign, value // 3600, value // 60 % 60)
    if value % 60 ~= 0 then text = text .. string.format(":%02d", value % 60) end
    return text
end
function M.duration_text(value)
    local sign = value < 0 and "-" or ""
    value = math.abs(value)
    return string.format("%s%d:%02d:%02d", sign, value // 3600, value // 60 % 60, value % 60)
end
function M.clock_text(value)
    local text = string.format("%d:%02d", value // 3600, value // 60 % 60)
    if value % 60 ~= 0 then text = text .. string.format(":%02d", value % 60) end
    return text
end
function M.state_text(period) return M.offset_text(period.offset) .. " " .. (period.dst and "DST" or "STD") .. " " .. period.abbreviation end
function M.change_text(time, before, after) return M.ut_text(time) .. " " .. M.state_text(before) .. " -> " .. M.state_text(after) end
function M.write_lines(path, lines)
    local file = assert(io.open(path, "w"))
    for _, line in ipairs(lines) do file:write(line, "\n") end
    file:close()
end
function M.write_blocks(path, blocks)
    local lines = {}
    for index, block in ipairs(blocks) do
        if index > 1 then lines[#lines + 1] = "" end
        for _, line in ipairs(block) do lines[#lines + 1] = line end
    end
    M.write_lines(path, lines)
end
return M
