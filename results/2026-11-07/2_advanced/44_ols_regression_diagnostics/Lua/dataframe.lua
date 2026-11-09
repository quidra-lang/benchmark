local M = {}
local function split(line, separator)
    local result = {}
    for value in line:gmatch(separator == "," and "[^,]+" or "%S+") do
        result[#result + 1] = value
    end
    return result
end
function M.lines(path)
    local result = {}
    for line in io.lines(path) do
        result[#result + 1] = line
    end
    return result
end
function M.read_csv(path, known_kinds)
    local lines = M.lines(path)
    local columns, records, kinds = split(lines[1], ","), {}, {}
    for index = 2, #lines do
        records[#records + 1] = split(lines[index], ",")
    end
    for column, name in ipairs(columns) do
        local categorical = known_kinds and known_kinds[name] == "categorical" or false
        if not known_kinds then
            for _, record in ipairs(records) do
                if record[column] ~= "NA" and record[column]:match("^[A-Z]") then
                    categorical = true
                end
            end
        end
        kinds[name] = categorical and "categorical" or "numeric"
    end
    local rows = {}
    for _, record in ipairs(records) do
        local row = {}
        for column, name in ipairs(columns) do
            local value = record[column]
            if value ~= "NA" then
                row[name] = kinds[name] == "numeric" and (tonumber(value) + 0.0) or value
            end
        end
        rows[#rows + 1] = row
    end
    return {columns = columns, kinds = kinds, rows = rows}
end
function M.read_params()
    local result = {}
    for line in io.lines("input/params.txt") do
        local values = split(line, " ")
        if values[1] == "PLOT" then
            result.PLOT = {tonumber(values[2]), tonumber(values[3]), tonumber(values[4])}
        else
            result[values[1]] = tonumber(values[2])
        end
    end
    return result
end
return M
