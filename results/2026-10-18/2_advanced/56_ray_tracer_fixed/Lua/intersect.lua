local fixed = require("fixed_point")
local vector = require("vector3")
local M = {}
function M.slab(low, high, origin, direction)
    local near, far, near_axis, far_axis
    for axis = 1, 3 do
        local component = direction[axis]
        if component == 0 then
            if origin[axis] < low[axis] or origin[axis] > high[axis] then return nil end
        else
            local a, b = ((low[axis] - origin[axis]) * 4096) // component, ((high[axis] - origin[axis]) * 4096) // component
            local entry, leave = math.min(a, b), math.max(a, b)
            if not near or entry > near then near, near_axis = entry, axis end
            if not far or leave < far then far, far_axis = leave, axis end
        end
    end
    if near > far then return nil end
    return {near, near_axis, far, far_axis}
end
function M.candidate(object, origin, direction, epsilon)
    if object.kind == "sphere" then
        local oc = vector.sub(origin, object.center)
        local b = vector.dot(oc, direction)
        local center_t = (-b * 4096) // vector.dot(direction, direction)
        local h = vector.add(oc, vector.scale(direction, center_t))
        local q = (object.radius * object.radius) // 4096 - vector.dot(h, h)
        if q < 0 then return nil end
        local width = (fixed.isqrt(q * 4096) * 4096) // vector.length(direction)
        local distance = center_t - width
        if distance <= epsilon then distance = center_t + width end
        if distance > epsilon then return {distance} end
    elseif object.kind == "plane" then
        local denominator = vector.dot(direction, object.normal)
        if denominator == 0 then return nil end
        local distance = (vector.dot(vector.sub(object.point, origin), object.normal) * 4096) // denominator
        if distance > epsilon then return {distance} end
    else
        local interval = M.slab(object.low, object.high, origin, direction)
        if not interval then return nil end
        if interval[1] > epsilon then return {interval[1], true, interval[2]} end
        if interval[3] > epsilon then return {interval[3], false, interval[4]} end
    end
end
function M.outward(object, point, direction, hit)
    if object.kind == "sphere" then return vector.norm(vector.sub(point, object.center)) end
    if object.kind == "plane" then return object.normal end
    local axis, sign = hit[3], direction[hit[3]] > 0 and 1 or -1
    if hit[2] then sign = -sign end
    local result = {0, 0, 0}
    result[axis] = sign * 4096
    return result
end
function M.bounds(object, margin)
    if object.kind == "plane" then return nil end
    local low, high = {}, {}
    for axis = 1, 3 do
        if object.kind == "sphere" then
            low[axis], high[axis] = object.center[axis] - object.radius - margin, object.center[axis] + object.radius + margin
        else low[axis], high[axis] = object.low[axis] - margin, object.high[axis] + margin end
    end
    return {low, high}
end
return M
