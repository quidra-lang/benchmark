local M = {}
function M.build(plan, types)
    local current, level, segments, length = plan.departure + plan.delay + 0.0, plan.level + plan.offset, {}, 0.0
    local times = {{current, level}}
    local function segment(leg, phase, ts, te, start, velocity, finish)
        segments[#segments + 1] = {number = #segments + 1, leg = leg, phase = phase, ts = ts, te = te, start = start, velocity = velocity, finish = finish}
    end
    for leg = 1, #plan.waypoints - 1 do
        local a, b = plan.waypoints[leg], plan.waypoints[leg + 1]
        local dx, dy = b.x - a.x, b.y - a.y
        local distance = math.sqrt(dx * dx + dy * dy) / 10
        local duration = distance * 3600 / plan.speed
        local vx, vy = (dx / 10) / duration, (dy / 10) / duration
        length = length + distance
        local target = b.level and b.level + plan.offset or level
        local x, y, xq, yq = a.x / 10, a.y / 10, b.x / 10, b.y / 10
        if target == level then segment(leg, 'LVL', current, current + duration, {x, y, level * 100}, {vx, vy, 0.0}, {xq, yq, target * 100})
        else
            local climbing = target > level
            local rate = climbing and types[plan.type].climb or types[plan.type].descent
            local vz = climbing and rate / 60 or -(rate / 60)
            local change_time = math.abs(target - level) * 6000 / rate
            local point = {x + vx * change_time, y + vy * change_time, target * 100}
            segment(leg, climbing and 'CLB' or 'DES', current, current + change_time, {x, y, level * 100}, {vx, vy, vz}, point)
            segment(leg, 'LVL', current + change_time, current + duration, point, {vx, vy, 0.0}, {xq, yq, target * 100})
        end
        current, level = current + duration, target
        times[#times + 1] = {current, level}
    end
    return {segments = segments, arrival = current, length = length, waypoint_times = times}
end
function M.position(segment, time)
    local elapsed, point = time - segment.ts, {}
    for i = 1, 3 do point[i] = segment.start[i] + segment.velocity[i] * elapsed end
    return point
end
function M.active_segment(trajectory, time)
    local segments = trajectory.segments
    if time < segments[1].ts or time >= segments[#segments].te then return nil end
    for _, segment in ipairs(segments) do if segment.ts <= time and time < segment.te then return segment end end
    return nil
end
function M.current_position(trajectory, time)
    local segment = M.active_segment(trajectory, time)
    if not segment then return nil end
    return M.position(segment, time), segment
end
return M
