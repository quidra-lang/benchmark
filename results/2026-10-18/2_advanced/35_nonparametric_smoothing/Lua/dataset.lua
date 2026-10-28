local M = {}
function M.hundredths(text)
    return tonumber((text:gsub("%.", "")))
end
local function fields(text, separator)
    local values = {}
    for value in text:gmatch("[^" .. separator .. "]+") do
        values[#values + 1] = value
    end
    return values
end
function M.read()
    local series, names, tests, settings = {}, {}, {}, {}
    local first = true
    for line in io.lines("input/series.csv") do
        if first then
            first = false
        else
            local row = fields(line, ",")
            if not series[row[1]] then
                series[row[1]] = {}
                names[#names + 1] = row[1]
            end
            local points = series[row[1]]
            points[#points + 1] = {M.hundredths(row[2]), M.hundredths(row[3])}
        end
    end
    for _, name in ipairs(names) do
        table.sort(series[name], function(a, b) return a[1] < b[1] end)
    end
    first = true
    for line in io.lines("input/test_points.csv") do
        if first then
            first = false
        else
            local row = fields(line, ",")
            tests[#tests + 1] = {row[1], M.hundredths(row[2])}
        end
    end
    for line in io.lines("input/params.txt") do
        local row = fields(line, " ")
        local key = table.remove(row, 1)
        settings[key] = row
    end
    for _, key in ipairs({"ROBUST_ITERATIONS", "CV_FOLDS", "GRID_POINTS", "BAND_Z", "OUTLIER_THRESHOLD"}) do
        settings[key] = tonumber(settings[key][1])
    end
    for _, key in ipairs({"BOOTSTRAP", "PLOT_SIZE"}) do
        for i, value in ipairs(settings[key]) do
            settings[key][i] = tonumber(value)
        end
    end
    return series, names, tests, settings
end
return M
