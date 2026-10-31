local M = {}
local function fields(line, separator)
    local result = {}
    for value in line:gmatch(separator == "," and "[^,]+" or "%S+") do
        result[#result + 1] = value
    end
    return result
end
function M.read()
    local settings = {}
    for line in io.lines("input/params.txt") do
        local values = fields(line, " ")
        local key = table.remove(values, 1)
        settings[key] = values
    end
    local params = {
        groups = settings.GROUPS, report_times = {}, tau = tonumber(settings.TAU[1]),
        width = tonumber(settings.LIFE_TABLE[1]), intervals = tonumber(settings.LIFE_TABLE[2]),
        strata = settings.STRATA[1], subgroups = settings.SUBGROUPS,
        landmark = tonumber(settings.LANDMARK[1]), covariates = settings.COX,
        residuals = tonumber(settings.RESIDUALS[1]), plot = {}
    }
    for _, value in ipairs(settings.REPORT_TIMES) do
        params.report_times[#params.report_times + 1] = tonumber(value)
    end
    for _, value in ipairs(settings.PLOT) do
        params.plot[#params.plot + 1] = tonumber(value)
    end
    local subjects = {}
    for line in io.lines("input/subjects.csv") do
        if line:sub(1, 3) ~= "id," then
            local row = fields(line, ",")
            subjects[#subjects + 1] = {
                id = tonumber(row[1]), group = row[2], time = tonumber(row[3]),
                event = tonumber(row[4]), age = tonumber(row[5]), sex = row[6], stage = tonumber(row[7])
            }
        end
    end
    table.sort(subjects, function(a, b) return a.id < b.id end)
    return subjects, params
end
return M
