local evaluation = require("evaluation")
local M = {}
function M.real(value)
    local text = string.format("%.4f", value)
    return text == "-0.0000" and "0.0000" or text
end
function M.reals(values)
    local fields = {}
    for index, value in ipairs(values) do
        fields[index] = M.real(value)
    end
    return table.concat(fields, " ")
end
function M.fraction(value)
    return not value and "-" or value[1] .. "/" .. value[2] .. " " .. M.real(value[1] / value[2])
end
function M.ratio(a, b)
    return M.fraction(evaluation.fraction(a, b))
end
function M.cell(value, low, high, size)
    return math.floor((value - low) / (high - low) * (size - 1) + 0.5)
end
function M.frame(grid)
    local border = "+" .. string.rep("-", #grid[1]) .. "+"
    local result = {border}
    for _, row in ipairs(grid) do
        result[#result + 1] = "|" .. table.concat(row) .. "|"
    end
    result[#result + 1] = border
    return result
end
function M.join_sections(sections)
    local result = {}
    for index, lines in ipairs(sections) do
        if index > 1 then
            result[#result + 1] = ""
        end
        for _, line in ipairs(lines) do
            result[#result + 1] = line
        end
    end
    return result
end
function M.save(name, lines)
    local file = assert(io.open("output/" .. name, "w"))
    for _, line in ipairs(lines) do
        file:write(line, "\n")
    end
    file:close()
end
return M
