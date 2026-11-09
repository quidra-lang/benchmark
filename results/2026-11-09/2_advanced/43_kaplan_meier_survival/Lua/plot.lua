local estimator = require("estimators")
local M = {}
function M.curves(groups, collections, estimates, width, height, time_limit)
    local cells = {}
    for band = 0, height - 1 do
        cells[band] = {}
        for column = 1, width do
            cells[band][column] = " "
        end
    end
    for index, group in ipairs(groups) do
        local letter = string.char(64 + index)
        local maximum = 0
        for _, subject in ipairs(collections[group]) do
            maximum = math.max(maximum, subject.time)
        end
        local previous
        for column = 0, width - 1 do
            local moment = column * (time_limit // width)
            if moment > maximum then
                break
            end
            local survival = estimator.row_at(estimates[group], moment).survival
            local band = math.min(height - 1, math.floor(survival * height))
            local last = band
            if previous then
                last = math.max(band, previous - 1)
            end
            for vertical = band, last do
                local cell = cells[vertical][column + 1]
                cells[vertical][column + 1] = cell == " " and letter or cell == letter and letter or "*"
            end
            previous = band
        end
    end
    local border = "   +" .. string.rep("-", width) .. "+"
    local result = {border}
    for band = height - 1, 0, -1 do
        result[#result + 1] = string.format("%3d|%s|", 100 * band // height, table.concat(cells[band]))
    end
    result[#result + 1] = border
    return result
end
return M
