local tests = require("tests")
local M = {}

function M.real(value)
    local text = string.format("%.4f", value)
    return text == "-0.0000" and "0.0000" or text
end

function M.p_value(a, b)
    a, b = tests.reduced_fraction(a, b)
    return string.format("%d/%d %s", a, b, M.real(a / b))
end

function M.number_list(numbers)
    if #numbers == 0 then return "none" end
    table.sort(numbers)
    return table.concat(numbers, " ")
end

function M.bin_number(value, low, high, bins)
    return math.min(math.floor(bins * (value - low) / (high - low)), bins - 1) + 1
end

function M.bar(count, top)
    return string.rep("#", (40 * count + top - 1) // top)
end

function M.write_files(files)
    assert(os.execute('mkdir -p "output"'))
    for _, entry in ipairs(files) do
        local file = assert(io.open("output/" .. entry[1], "w"))
        file:write(table.concat(entry[2], "\n"), "\n")
        file:close()
    end
end

return M
