local M = {}

function M.fixed(value, places)
    local text = string.format("%." .. (places or 6) .. "f", value)
    return text:sub(1, 1) == "-" and tonumber(text) == 0 and text:sub(2) or text
end

function M.scaled(value, places) return math.floor(value * 10 ^ (places or 6) + 0.5) end

function M.fraction(numerator, denominator)
    local a, b = math.abs(numerator), denominator
    while b ~= 0 do a, b = b, a % b end
    numerator, denominator = numerator // a, denominator // a
    return numerator .. "/" .. denominator .. " " .. M.fixed(numerator / denominator, 4)
end

function M.write(name, lines)
    local handle = assert(io.open("output/" .. name, "w"))
    handle:write(table.concat(lines, "\n"), "\n")
    handle:close()
end

return M
