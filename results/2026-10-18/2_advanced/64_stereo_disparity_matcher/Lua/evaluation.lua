local R = require("refinement")
local E = { region_order = { "nonocc", "all", "disc" } }
function E.regions(truth, width, height)
    local result = { all = {}, nonocc = {}, disc = {}, occluded = {} }
    for y = 0, height - 1 do
        local nearest = {}
        for x = 0, width - 1 do
            local g = truth[y * width + x + 1]
            if g ~= 0 then nearest[x - g] = math.max(nearest[x - g] or 0, g) end
        end
        for x = 0, width - 1 do
            local p = y * width + x + 1
            local g = truth[p]
            if g ~= 0 then
                result.all[#result.all + 1] = p
                if x < g or nearest[x - g] > g then result.occluded[#result.occluded + 1] = p
                else
                    result.nonocc[#result.nonocc + 1] = p
                    local edge = false
                    for yy = math.max(0, y - 1), math.min(height - 1, y + 1) do
                        for xx = math.max(0, x - 1), math.min(width - 1, x + 1) do
                            local value = truth[yy * width + xx + 1]
                            if value ~= 0 and math.abs(value - g) >= 2 then edge = true end
                        end
                    end
                    if edge then result.disc[#result.disc + 1] = p end
                end
            end
        end
    end
    return result
end
function E.evaluate(image, truth, region)
    local result = { pixels = #region, valid = 0, bad1 = 0, bad2 = 0, error_sum = 0, exact = 0 }
    for _, p in ipairs(region) do
        local disparity = image[p]
        if disparity == 0 then result.bad1, result.bad2 = result.bad1 + 1, result.bad2 + 1
        else
            local error_value = math.abs(disparity - truth[p])
            result.valid, result.error_sum = result.valid + 1, result.error_sum + error_value
            if error_value > 1 then result.bad1 = result.bad1 + 1 end
            if error_value > 2 then result.bad2 = result.bad2 + 1 end
            if error_value == 0 then result.exact = result.exact + 1 end
        end
    end
    result.mae = result.valid > 0 and R.two(result.error_sum, result.valid) or "-"
    return result
end
function E.ratio(a, b)
    if b == 0 then return "0/1 0.00" end
    local x, y = a, b
    while y ~= 0 do x, y = y, x % y end
    return (a // x) .. "/" .. (b // x) .. " " .. R.two(100 * a, b)
end
return E
