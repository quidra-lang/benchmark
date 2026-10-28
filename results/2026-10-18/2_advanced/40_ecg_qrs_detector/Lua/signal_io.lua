local M = {}
function M.read_ecg()
    local result = {}
    for line in io.lines("input/ecg.csv") do
        if line ~= "sample,microvolts" then
            result[#result + 1] = tonumber(line:match(",(.+)$"))
        end
    end
    return result
end
function M.read_annotations()
    local result = {}
    for line in io.lines("input/annotations.csv") do
        if line ~= "sample,label" then
            local sample, label = line:match("^(%d+),([NVA])$")
            result[#result + 1] = {sample = tonumber(sample), label = label}
        end
    end
    return result
end
function M.read_params()
    local result = {}
    for line in io.lines("input/params.txt") do
        local key, value = line:match("^(%S+) (%S+)$")
        result[key] = tonumber(value)
    end
    return result
end
function M.write_lines(name, lines)
    local file = assert(io.open("output/" .. name, "w"))
    for _, line in ipairs(lines) do
        file:write(line, "\n")
    end
    file:close()
end
return M
