local M = {}
local function fields(line, pattern)
    local result = {}
    for value in line:gmatch(pattern or '%S+') do result[#result + 1] = value end
    return result
end
function M.clone_plan(plan)
    local copy = {}
    for key, value in pairs(plan) do copy[key] = value end
    copy.history = {}
    for _, name in ipairs(plan.history) do copy.history[#copy.history + 1] = name end
    return copy
end
function M.level_list(plan)
    local levels = {plan.level + plan.offset}
    for i = 2, #plan.waypoints do local level = plan.waypoints[i].level; if level then levels[#levels + 1] = level + plan.offset end end
    return levels
end
function M.load_all()
    local plans, types, sectors, params = {}, {}, {}, {}
    for line in io.lines('input/aircraft.txt') do local f = fields(line); types[f[1]] = {climb = tonumber(f[2]), descent = tonumber(f[3]), minimum = tonumber(f[4])} end
    for line in io.lines('input/sectors.txt') do
        local f = fields(line)
        sectors[#sectors + 1] = {name = f[1], x1 = tonumber(f[2]), y1 = tonumber(f[3]), x2 = tonumber(f[4]), y2 = tonumber(f[5]), lower = tonumber(f[6]), upper = tonumber(f[7]), capacity = tonumber(f[8]), index = #sectors + 1}
    end
    local first = true
    for line in io.lines('input/flights.csv') do
        if first then first = false
        else
            local f, waypoints = fields(line, '[^,]+'), {}
            for _, part in ipairs(fields(f[6])) do
                local coordinates = fields(part, '[^:]+')
                waypoints[#waypoints + 1] = {x = tonumber(coordinates[1]), y = tonumber(coordinates[2]), level = tonumber(coordinates[3])}
            end
            plans[f[1]] = {callsign = f[1], type = f[2], departure = tonumber(f[3]), level = tonumber(f[4]), speed_initial = tonumber(f[5]), speed = tonumber(f[5]), waypoints = waypoints, delay = 0, offset = 0, history = {}}
        end
    end
    for line in io.lines('input/params.txt') do
        local f = fields(line)
        local key = table.remove(f, 1)
        for i, value in ipairs(f) do f[i] = tonumber(value) end
        if key == 'separation' then params.dh, params.dv = f[1], f[2]
        elseif key == 'lookahead' then params.lookahead = f[1]
        elseif key == 'max_delay' then params.max_delay = f[1]
        elseif key == 'levels' then params.level_min, params.level_max = f[1], f[2]
        elseif key == 'sampling' then params.sample_start, params.sample_end = f[1], f[2]
        elseif key == 'radar' then params.radar = f
        elseif key == 'snapshots' then params.snapshots = f
        elseif key == 'leader' then params.leader = f[1]
        else params.alert = f[1] end
    end
    return plans, types, sectors, params
end
return M
