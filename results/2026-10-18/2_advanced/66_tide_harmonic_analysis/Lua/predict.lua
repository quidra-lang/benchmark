local fit = require('harmonic_fit')
local M = {}
function M.height(model, t)
    local h = model.mean_level
    for _, c in ipairs(model.selected) do
        local k = model.constants[c.name]
        local theta = fit.angle(c.speed, t)
        h = h + (k.a * math.cos(theta) + k.b * math.sin(theta))
    end
    return h
end
function M.hours(model, start, count)
    local out = {}
    for i = 0, count do out[i + 1] = M.height(model, start + i) end
    return out
end
function M.extrema(model, s)
    local count = s.prediction_hours * 60 // s.grid_minutes
    local heights, out = {}, {}
    for i = 0, count do heights[i] = M.height(model, (s.prediction_start * 60 + i * s.grid_minutes) / 60) end
    for i = 1, count - 1 do
        local l, c, r = heights[i - 1], heights[i], heights[i + 1]
        local kind
        if l < c and c > r then kind = 'high' elseif l > c and c < r then kind = 'low' end
        if kind then
            local delta = (l - r) / (2 * (l - 2 * c + r))
            local minute = s.prediction_start * 60 + i * s.grid_minutes + delta * s.grid_minutes
            out[#out + 1] = {kind = kind, minute = minute, height = c - (l - r) * delta / 4}
        end
    end
    return out
end
return M
