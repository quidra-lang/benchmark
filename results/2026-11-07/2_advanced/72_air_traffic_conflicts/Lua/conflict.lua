local trajectory = require('trajectory')
local M = {}
function M.loss_interval(relative, velocity, t1, t2, dh, dv)
    local px, py, pz = table.unpack(relative)
    local wx, wy, wz = table.unpack(velocity)
    local qa, qb, qc = wx * wx + wy * wy, 2 * (px * wx + py * wy), (px * px + py * py) - dh * dh
    local lo, hi = t1, t2
    if qa < 1e-12 then if qc >= 0 then return nil end
    else
        local discriminant = qb * qb - 4 * qa * qc
        if discriminant <= 0 then return nil end
        local root = math.sqrt(discriminant)
        lo, hi = math.max(lo, t1 + (-qb - root) / (2 * qa)), math.min(hi, t1 + (-qb + root) / (2 * qa))
    end
    if wz == 0 then if math.abs(pz) >= dv then return nil end
    else
        local r1, r2 = (-dv - pz) / wz, (dv - pz) / wz
        lo, hi = math.max(lo, t1 + math.min(r1, r2)), math.min(hi, t1 + math.max(r1, r2))
    end
    if hi - lo <= 1e-6 then return nil end
    local tc = qa >= 1e-12 and t1 + (-qb / (2 * qa)) or t1
    tc = math.min(math.max(tc, lo), hi)
    local tau = tc - t1
    local ex, ey = px + wx * tau, py + wy * tau
    return {lo = lo, hi = hi, tc = tc, distance = math.sqrt(ex * ex + ey * ey), vertical = math.abs(pz + wz * tau)}
end
function M.less(a, b)
    if a.start ~= b.start then return a.start < b.start end
    if a.a ~= b.a then return a.a < b.a end
    return a.b < b.b
end
function M.pair_conflicts(name_a, trajectory_a, name_b, trajectory_b, dh, dv)
    local pieces = {}
    for _, a in ipairs(trajectory_a.segments) do
        for _, b in ipairs(trajectory_b.segments) do
            local t1, t2 = math.max(a.ts, b.ts), math.min(a.te, b.te)
            if t1 < t2 then
                local pa, pb, relative, velocity = trajectory.position(a, t1), trajectory.position(b, t1), {}, {}
                for i = 1, 3 do relative[i], velocity[i] = pa[i] - pb[i], a.velocity[i] - b.velocity[i] end
                local interval = M.loss_interval(relative, velocity, t1, t2, dh, dv)
                if interval then interval.a_segment, interval.b_segment, interval.serial = a, b, #pieces + 1; pieces[#pieces + 1] = interval end
            end
        end
    end
    table.sort(pieces, function(a, b) return a.lo < b.lo or a.lo == b.lo and a.serial < b.serial end)
    local conflicts = {}
    for _, piece in ipairs(pieces) do
        local last = conflicts[#conflicts]
        if not last or piece.lo - last.finish > 1e-6 then conflicts[#conflicts + 1] = {a = name_a, b = name_b, name = name_a .. '-' .. name_b, start = piece.lo, finish = piece.hi, pieces = {piece}, closest = piece}
        else
            last.pieces[#last.pieces + 1], last.finish = piece, piece.hi
            if piece.distance < last.closest.distance - 1e-9 then last.closest = piece end
        end
    end
    return conflicts
end
function M.all_conflicts(trajectories, dh, dv)
    local names, conflicts = {}, {}
    for name in pairs(trajectories) do names[#names + 1] = name end
    table.sort(names)
    for i = 1, #names do
        for j = i + 1, #names do for _, found in ipairs(M.pair_conflicts(names[i], trajectories[names[i]], names[j], trajectories[names[j]], dh, dv)) do conflicts[#conflicts + 1] = found end end
    end
    table.sort(conflicts, M.less)
    return conflicts
end
return M
