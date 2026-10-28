local M = {}
local function fields(line, pattern)
    local result = {}
    for value in line:gmatch(pattern) do
        result[#result + 1] = value
    end
    return result
end
local function read_table(path)
    local variables, ids, rows = {}, {}, {}
    for line in io.lines(path) do
        local values = fields(line, "[^,]+")
        if #variables == 0 then
            for index = 2, #values do
                variables[#variables + 1] = values[index]
            end
        else
            ids[#ids + 1] = values[1]
            local row = {}
            for index = 2, #values do
                if values[index] == "NA" then
                    row[#row + 1] = false
                else
                    row[#row + 1] = tonumber(values[index]) + 0.0
                end
            end
            rows[#rows + 1] = row
        end
    end
    return variables, ids, rows
end
function M.read()
    local variables, ids, rows = read_table("input/data.csv")
    local _, supplementary_ids, supplementary = read_table("input/supplementary.csv")
    local settings = {}
    for line in io.lines("input/params.txt") do
        local values = fields(line, "%S+")
        local key = table.remove(values, 1)
        settings[key] = values
    end
    local params = {
        missing = settings.MISSING[1], scaling = settings.SCALING[1], components = settings.COMPONENTS[1],
        cumulative = (tonumber(settings.CUMULATIVE_TARGET[1]) + 0.0), repetitions = tonumber(settings.PARALLEL[1]),
        seed = tonumber(settings.PARALLEL[2]), t2_limit = (tonumber(settings.T2_LIMIT[1]) + 0.0), spe_limit = (tonumber(settings.SPE_LIMIT[1]) + 0.0),
        cycles = tonumber(settings.VARIMAX_CYCLES[1]), top = tonumber(settings.TOP_ROWS[1]),
        scree_width = tonumber(settings.SCREE_WIDTH[1]), biplot_width = tonumber(settings.BIPLOT_SIZE[1]),
        biplot_height = tonumber(settings.BIPLOT_SIZE[2]), radius = tonumber(settings.CIRCLE_RADIUS[1]),
        diagnostic_width = tonumber(settings.DIAGNOSTIC_SIZE[1]), diagnostic_height = tonumber(settings.DIAGNOSTIC_SIZE[2])
    }
    return {variables = variables, ids = ids, rows = rows, supplementary_ids = supplementary_ids,
        supplementary = supplementary, params = params}
end
return M
