local plans = require('flight_plans')
local M = {}
function M.priority_order(a, b)
    local x, y = a.departure + a.delay, b.departure + b.delay
    if x > y or x == y and a.callsign > b.callsign then return a.callsign, b.callsign end
    return b.callsign, a.callsign
end
function M.manoeuvres(maximum)
    local result = {{'level_up', 10}, {'level_down', -10}, {'speed_down'}}
    for delay = 60, maximum, 60 do result[#result + 1] = {'delay_' .. delay, delay} end
    return result
end
function M.propose(plan, name, amount, types, params)
    local changed = plans.clone_plan(plan)
    if name == 'level_up' or name == 'level_down' then
        changed.offset = changed.offset + amount
        for _, level in ipairs(plans.level_list(changed)) do if level < params.level_min or level > params.level_max then return nil end end
    elseif name == 'speed_down' then
        changed.speed = changed.speed * 9 // 10
        if changed.speed < types[changed.type].minimum then return nil end
    else changed.delay = changed.delay + amount end
    return changed
end
return M
