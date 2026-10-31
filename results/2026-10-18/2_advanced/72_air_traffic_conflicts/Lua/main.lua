package.path = 'Lua/?.lua;' .. package.path
local flight_plans = require('flight_plans')
local trajectory = require('trajectory')
local conflict = require('conflict')
local resolution = require('resolution')
local report = require('report')
local decimal = report.decimal
local initial, types, sectors, params = flight_plans.load_all()
local names = {}
for name in pairs(initial) do names[#names + 1] = name end
table.sort(names)
local function append(destination, source) for _, value in ipairs(source) do destination[#destination + 1] = value end end
local function keys(set)
    local result = {}
    for key in pairs(set) do result[#result + 1] = key end
    table.sort(result)
    return result
end
local function increment(counts, key) counts[key] = (counts[key] or 0) + 1 end
local times = {}
for time = params.sample_start, params.sample_end - 1, 60 do times[#times + 1] = time end
local initial_trajectories, final, final_trajectories = {}, {}, {}
for _, name in ipairs(names) do initial_trajectories[name] = trajectory.build(initial[name], types); final[name] = flight_plans.clone_plan(initial[name]); final_trajectories[name] = initial_trajectories[name] end
local initial_conflicts = conflict.all_conflicts(initial_trajectories, params.dh, params.dv)
local unresolved_pairs, resolved_pairs, unresolved_conflicts, rounds = {}, {}, {}, {}
local function find_blocker(changed, new_trajectory, partner, target_start)
    local blockers = {}
    for _, other in ipairs(names) do
        if other ~= changed then
            local a, b = changed, other
            if a > b then a, b = b, a end
            if not unresolved_pairs[a .. '-' .. b] then
                local ta, tb = a == changed and new_trajectory or final_trajectories[a], b == changed and new_trajectory or final_trajectories[b]
                for _, found in ipairs(conflict.pair_conflicts(a, ta, b, tb, params.dh, params.dv)) do
                    if other == partner or found.start < target_start + params.lookahead then blockers[#blockers + 1] = found end
                end
            end
        end
    end
    table.sort(blockers, conflict.less)
    return blockers[1]
end
while true do
    local target
    for _, found in ipairs(conflict.all_conflicts(final_trajectories, params.dh, params.dv)) do if not unresolved_pairs[found.name] then target = found; break end end
    if not target then break end
    local first, second = resolution.priority_order(final[target.a], final[target.b])
    local round = {number = #rounds + 1, target = target, trials = {}}
    for _, pair in ipairs({{first, second}, {second, first}}) do
        if round.accepted then break end
        local aircraft, partner = pair[1], pair[2]
        for _, manoeuvre in ipairs(resolution.manoeuvres(params.max_delay)) do
            local name, amount = table.unpack(manoeuvre)
            local proposal = resolution.propose(final[aircraft], name, amount, types, params)
            local trial = {aircraft = aircraft, name = name}
            if not proposal then trial.status = 'infeasible'
            else
                local new_trajectory = trajectory.build(proposal, types)
                local blocker = find_blocker(aircraft, new_trajectory, partner, target.start)
                if blocker then trial.status, trial.blocker = 'blocked', blocker
                else
                    trial.status = 'accepted'
                    proposal.history[#proposal.history + 1] = name
                    final[aircraft], final_trajectories[aircraft], round.accepted = proposal, new_trajectory, trial
                end
            end
            round.trials[#round.trials + 1] = trial
            if round.accepted then break end
        end
    end
    if round.accepted then resolved_pairs[target.name] = true else unresolved_pairs[target.name] = true; unresolved_conflicts[#unresolved_conflicts + 1] = target end
    rounds[#rounds + 1] = round
end
local final_conflicts = conflict.all_conflicts(final_trajectories, params.dh, params.dv)
local final_pairs = {}
for _, found in ipairs(final_conflicts) do final_pairs[found.name] = true end
local function track(segment)
    local angle = math.atan(segment.velocity[1], segment.velocity[2]) * 180 / 3.141592653589793
    return angle < 0 and angle + 360 or angle
end
local function contains(sector, point)
    return sector.x1 / 10 <= point[1] and point[1] < sector.x2 / 10 and sector.y1 / 10 <= point[2] and point[2] < sector.y2 / 10 and sector.lower * 100 <= point[3] and point[3] < sector.upper * 100
end
local function classify(conflicts, is_final)
    for _, found in ipairs(conflicts) do
        local piece = found.closest
        local a, b, tc = piece.a_segment, piece.b_segment, piece.tc
        local pa, pb = trajectory.position(a, tc), trajectory.position(b, tc)
        found.level_a, found.level_b, found.track_a, found.track_b = pa[3] / 100, pb[3] / 100, track(a), track(b)
        local angle = math.abs(found.track_a - found.track_b)
        found.angle = angle > 180 and 360 - angle or angle
        local dot = a.velocity[1] * b.velocity[1] + a.velocity[2] * b.velocity[2]
        local cross = a.velocity[1] * b.velocity[2] - a.velocity[2] * b.velocity[1]
        found.geometry = dot * dot > cross * cross and (dot < 0 and 'head_on' or 'trailing') or 'crossing'
        found.severity = 10 * piece.distance < 4 * params.dh and 'HIGH' or 10 * piece.distance < 7 * params.dh and 'MEDIUM' or 'LOW'
        local midpoint = {}
        for i = 1, 3 do midpoint[i] = (pa[i] + pb[i]) / 2 end
        found.sector = '-'
        for _, sector in ipairs(sectors) do if contains(sector, midpoint) then found.sector = sector.name; break end end
        found.outcome = (is_final or final_pairs[found.name]) and 'remaining' or resolved_pairs[found.name] and 'resolved' or 'indirect'
    end
end
classify(initial_conflicts, false); classify(final_conflicts, true)
local function active(conflicts, time)
    local result = {}
    for _, found in ipairs(conflicts) do if found.start <= time and time < found.finish then result[#result + 1] = found end end
    return result
end
local function involved(conflicts)
    local result = {}
    for _, found in ipairs(conflicts) do
        result[found.a], result[found.b] = result[found.a] or {}, result[found.b] or {}
        result[found.a][#result[found.a] + 1] = {found, found.b}
        result[found.b][#result[found.b] + 1] = {found, found.a}
    end
    return result
end
local function trajectories_csv()
    local lines = {'callsign,segment,leg,phase,t_start,t_end,x_start,y_start,fl_start,x_end,y_end,fl_end'}
    for _, name in ipairs(names) do
        for _, segment in ipairs(final_trajectories[name].segments) do
            local a, b = segment.start, segment.finish
            lines[#lines + 1] = table.concat({name, segment.number, segment.leg, segment.phase, decimal(segment.ts), decimal(segment.te), decimal(a[1]), decimal(a[2]), math.tointeger(a[3] / 100), decimal(b[1]), decimal(b[2]), math.tointeger(b[3] / 100)}, ',')
        end
    end
    return lines
end
local function conflict_lines(label, conflicts, trajectories)
    local lines = {'CONFLICTS plan=' .. label .. ' count=' .. #conflicts}
    local geometry, severity, total, minimum = {}, {}, 0.0, nil
    for number, found in ipairs(conflicts) do
        local piece = found.closest
        lines[#lines + 1] = 'CONFLICT ' .. number .. ' ' .. found.name .. ' start=' .. decimal(found.start) .. ' end=' .. decimal(found.finish) .. ' duration=' .. decimal(found.finish - found.start) .. ' outcome=' .. found.outcome
        lines[#lines + 1] = '  CPA t=' .. decimal(piece.tc) .. ' dist=' .. decimal(piece.distance) .. ' vert=' .. decimal(piece.vertical, 1) .. ' levels=' .. decimal(found.level_a, 2) .. '/' .. decimal(found.level_b, 2) .. ' tracks=' .. decimal(found.track_a, 1) .. '/' .. decimal(found.track_b, 1) .. ' angle=' .. decimal(found.angle, 1)
        lines[#lines + 1] = '  TYPE geometry=' .. found.geometry .. ' phases=' .. piece.a_segment.phase .. '/' .. piece.b_segment.phase .. ' segments=' .. piece.a_segment.number .. '/' .. piece.b_segment.number .. ' sector=' .. found.sector .. ' severity=' .. found.severity
        for _, section in ipairs(found.pieces) do lines[#lines + 1] = '  PIECE ' .. section.a_segment.number .. '/' .. section.b_segment.number .. ' ' .. decimal(section.lo) .. ' ' .. decimal(section.hi) end
        increment(geometry, found.geometry); increment(severity, found.severity)
        total = total + (found.finish - found.start)
        minimum = minimum and math.min(minimum, piece.distance) or piece.distance
    end
    lines[#lines + 1] = 'SUMMARY count=' .. #conflicts .. ' total=' .. decimal(total) .. ' min_dist=' .. (minimum and decimal(minimum) or '-') .. ' head_on=' .. (geometry.head_on or 0) .. ' crossing=' .. (geometry.crossing or 0) .. ' trailing=' .. (geometry.trailing or 0) .. ' high=' .. (severity.HIGH or 0) .. ' medium=' .. (severity.MEDIUM or 0) .. ' low=' .. (severity.LOW or 0)
    local flights = involved(conflicts)
    for _, name in ipairs(keys(flights)) do
        local partners, first = {}, math.huge
        for _, entry in ipairs(flights[name]) do partners[entry[2]] = true; first = math.min(first, entry[1].start) end
        lines[#lines + 1] = 'FLIGHT ' .. name .. ' conflicts=' .. #flights[name] .. ' first=' .. decimal(first) .. ' partners=' .. table.concat(keys(partners), ',')
    end
    lines[#lines + 1] = 'TIMELINE from=' .. params.sample_start .. ' to=' .. params.sample_end .. ' step=60'
    for _, name in ipairs(keys(flights)) do
        local symbols = {}
        for _, time in ipairs(times) do
            local symbol = '.'
            if trajectory.active_segment(trajectories[name], time) then
                symbol = '-'
                for _, entry in ipairs(flights[name]) do if entry[1].start <= time and time < entry[1].finish then symbol = 'X'; break end end
            end
            symbols[#symbols + 1] = symbol
        end
        lines[#lines + 1] = name .. ' ' .. table.concat(symbols)
    end
    return lines
end
local function resolution_lines()
    local lines, accepted_count, infeasible, blocked, trials, level_count, speed_count, delay_count = {}, 0, 0, 0, 0, 0, 0, 0
    for _, round in ipairs(rounds) do
        local target = round.target
        lines[#lines + 1] = 'ROUND ' .. round.number .. ' ' .. target.name .. ' start=' .. decimal(target.start) .. ' end=' .. decimal(target.finish) .. ' dist=' .. decimal(target.closest.distance)
        for _, trial in ipairs(round.trials) do
            trials = trials + 1
            local text = '  TRY ' .. trial.aircraft .. ' ' .. trial.name .. ' ' .. trial.status
            if trial.status == 'blocked' then blocked = blocked + 1; text = text .. ' ' .. trial.blocker.name .. ' start=' .. decimal(trial.blocker.start)
            elseif trial.status == 'infeasible' then infeasible = infeasible + 1 end
            lines[#lines + 1] = text
        end
        local accepted = round.accepted
        if accepted then
            accepted_count = accepted_count + 1
            if accepted.name:sub(1, 6) == 'level_' then level_count = level_count + 1 elseif accepted.name == 'speed_down' then speed_count = speed_count + 1 else delay_count = delay_count + 1 end
            lines[#lines + 1] = '  RESULT resolved ' .. accepted.aircraft .. ' ' .. accepted.name
        else lines[#lines + 1] = '  RESULT unresolved' end
    end
    local before, after = involved(initial_conflicts), involved(final_conflicts)
    local total_extra, total_delay = 0.0, 0
    for _, name in ipairs(names) do
        local old, new = initial[name], final[name]
        local old_arrival, new_arrival = initial_trajectories[name].arrival, final_trajectories[name].arrival
        local extra = new_arrival - old_arrival
        total_extra, total_delay = total_extra + extra, total_delay + new.delay
        lines[#lines + 1] = 'FLIGHT ' .. name .. ' departure=' .. (new.departure + new.delay) .. ' delay=' .. new.delay .. ' level=' .. report.signed(new.offset) .. ' speed=' .. old.speed .. '->' .. new.speed .. ' arrival=' .. decimal(old_arrival) .. '->' .. decimal(new_arrival) .. ' extra=' .. decimal(extra) .. ' length=' .. decimal(final_trajectories[name].length) .. ' conflicts=' .. #(before[name] or {}) .. '->' .. #(after[name] or {}) .. ' manoeuvres=' .. (#new.history > 0 and table.concat(new.history, ',') or '-')
    end
    for _, found in ipairs(unresolved_conflicts) do lines[#lines + 1] = 'UNRESOLVED ' .. found.name .. ' start=' .. decimal(found.start) .. ' dist=' .. decimal(found.closest.distance) end
    lines[#lines + 1] = 'TOTAL rounds=' .. #rounds .. ' resolved=' .. accepted_count .. ' unresolved=' .. #unresolved_conflicts .. ' level=' .. level_count .. ' speed=' .. speed_count .. ' delay=' .. delay_count .. ' total_delay=' .. total_delay .. ' total_extra=' .. decimal(total_extra) .. ' trials=' .. trials .. ' infeasible=' .. infeasible .. ' blocked=' .. blocked
    return lines
end

local function inside_segment_sector(segment, sector)
    local limits = {{sector.x1 / 10, sector.x2 / 10}, {sector.y1 / 10, sector.y2 / 10}, {sector.lower * 100, sector.upper * 100}}
    local lo, hi = segment.ts, segment.te
    for axis = 1, 3 do
        local p, v, low, high = segment.start[axis], segment.velocity[axis], limits[axis][1], limits[axis][2]
        if v == 0 then if p < low or p >= high then return nil end
        else
            local r1, r2 = (low - p) / v, (high - p) / v
            lo, hi = math.max(lo, segment.ts + math.min(r1, r2)), math.min(hi, segment.ts + math.max(r1, r2))
        end
    end
    if hi - lo <= 1e-6 then return nil end
    return lo, hi
end
local function sector_transits(trajectories)
    local all = {}
    for _, name in ipairs(names) do
        local transits = {}
        for sector_index, sector in ipairs(sectors) do
            local combined = {}
            for _, segment in ipairs(trajectories[name].segments) do
                local lo, hi = inside_segment_sector(segment, sector)
                if lo then
                    local previous = combined[#combined]
                    if previous and lo - previous[2] <= 1e-6 then previous[2] = hi else combined[#combined + 1] = {lo, hi} end
                end
            end
            for _, interval in ipairs(combined) do transits[#transits + 1] = {callsign = name, sector = sector.name, sector_index = sector_index, entry = interval[1], exit = interval[2], previous = '-', following = '-'} end
        end
        table.sort(transits, function(a, b) return a.entry < b.entry or a.entry == b.entry and a.sector_index < b.sector_index end)
        for i = 2, #transits do
            local previous, later = transits[i - 1], transits[i]
            if math.abs(later.entry - previous.exit) <= 1e-6 then previous.following, previous.following_index, later.previous = later.sector, later.sector_index, previous.sector end
        end
        append(all, transits)
    end
    return all
end
local initial_transits, final_transits = sector_transits(initial_trajectories), sector_transits(final_trajectories)
local function transit_lines()
    local lines = {'callsign,sector,entry,exit,duration,from,to'}
    for _, transit in ipairs(final_transits) do lines[#lines + 1] = table.concat({transit.callsign, transit.sector, decimal(transit.entry), decimal(transit.exit), decimal(transit.exit - transit.entry), transit.previous, transit.following}, ',') end
    return lines
end
local function occupancy_table(trajectories)
    local result = {}
    for i = 1, #sectors do result[i] = {}; for j = 1, #times do result[i][j] = 0 end end
    for j, time in ipairs(times) do
        for _, name in ipairs(names) do
            local point = trajectory.current_position(trajectories[name], time)
            if point then for i, sector in ipairs(sectors) do if contains(sector, point) then result[i][j] = result[i][j] + 1 end end end
        end
    end
    return result
end
local initial_occupancy, final_occupancy = occupancy_table(initial_trajectories), occupancy_table(final_trajectories)
local function sector_load_lines()
    local lines = {'sector,period,start,end,entries_initial,entries_final,peak_initial,peak_final,mean_final,capacity,status'}
    for s, sector in ipairs(sectors) do
        for first = 1, #times, 5 do
            local start_time, end_time = times[first], times[first] + 300
            local initial_peak, final_peak, total = 0, 0, 0
            for j = first, first + 4 do initial_peak, final_peak, total = math.max(initial_peak, initial_occupancy[s][j]), math.max(final_peak, final_occupancy[s][j]), total + final_occupancy[s][j] end
            local initial_entries, final_entries = 0, 0
            for _, transit in ipairs(initial_transits) do if transit.sector_index == s and start_time <= transit.entry and transit.entry < end_time then initial_entries = initial_entries + 1 end end
            for _, transit in ipairs(final_transits) do if transit.sector_index == s and start_time <= transit.entry and transit.entry < end_time then final_entries = final_entries + 1 end end
            local status = final_peak > sector.capacity and 'OVER' or initial_peak > sector.capacity and 'RELIEVED' or 'OK'
            lines[#lines + 1] = table.concat({sector.name, (first - 1) // 5 + 1, start_time, end_time, initial_entries, final_entries, initial_peak, final_peak, decimal(total / 5, 1), sector.capacity, status}, ',')
        end
    end
    return lines
end
local function level_usage(trajectories)
    local result = {}
    for _, name in ipairs(names) do
        for _, segment in ipairs(trajectories[name].segments) do
            if segment.phase == 'LVL' then
                local level = math.tointeger(segment.start[3] / 100)
                if not result[level] then result[level] = {flights = {}, time = 0.0} end
                result[level].flights[name] = true
                result[level].time = result[level].time + (segment.te - segment.ts)
            end
        end
    end
    return result
end
local function maximum(values)
    local biggest = values[1]
    for i = 2, #values do biggest = math.max(biggest, values[i]) end
    return biggest
end
local function sector_report()
    local lines = {}
    for s, sector in ipairs(sectors) do
        lines[#lines + 1] = 'SECTOR ' .. sector.name .. ' x=' .. sector.x1 .. '..' .. sector.x2 .. ' y=' .. sector.y1 .. '..' .. sector.y2 .. ' fl=' .. sector.lower .. '..' .. sector.upper .. ' capacity=' .. sector.capacity
        for _, version in ipairs({{'INITIAL', initial_transits, initial_occupancy, initial_conflicts}, {'FINAL', final_transits, final_occupancy, final_conflicts}}) do
            local entries, dwell, over, conflicts = 0, 0.0, 0, 0
            for _, transit in ipairs(version[2]) do if transit.sector_index == s then entries, dwell = entries + 1, dwell + (transit.exit - transit.entry) end end
            local occupancy = version[3][s]
            for first = 1, #times, 5 do local peak = 0; for j = first, first + 4 do peak = math.max(peak, occupancy[j]) end; if peak > sector.capacity then over = over + 1 end end
            for _, found in ipairs(version[4]) do if found.sector == sector.name then conflicts = conflicts + 1 end end
            lines[#lines + 1] = version[1] .. ' entries=' .. entries .. ' time=' .. decimal(dwell) .. ' mean=' .. (entries > 0 and decimal(dwell / entries) or '-') .. ' peak=' .. maximum(occupancy) .. ' over=' .. over .. ' conflicts=' .. conflicts
        end
        local rows, height = {}, math.max(sector.capacity + 1, maximum(final_occupancy[s]))
        for level = height, 1, -1 do
            local cells = {}
            for _, count in ipairs(final_occupancy[s]) do cells[#cells + 1] = count >= level and '#' or level == sector.capacity and '-' or '.' end
            rows[#rows + 1] = table.concat(cells)
        end
        append(lines, report.chart(rows))
    end
    local before, after, levels = level_usage(initial_trajectories), level_usage(final_trajectories), {}
    for level in pairs(before) do levels[level] = true end
    for level in pairs(after) do levels[level] = true end
    local ordered_levels = keys(levels)
    lines[#lines + 1] = 'LEVELS'
    for i = #ordered_levels, 1, -1 do
        local level = ordered_levels[i]
        local a, b = before[level] or {flights = {}, time = 0.0}, after[level] or {flights = {}, time = 0.0}
        lines[#lines + 1] = 'LEVEL ' .. level .. ' flights=' .. #keys(a.flights) .. '->' .. #keys(b.flights) .. ' time=' .. decimal(a.time) .. '->' .. decimal(b.time)
    end
    local handoffs, total = {}, 0
    for s = 1, #sectors do handoffs[s] = {} end
    for _, transit in ipairs(final_transits) do
        if transit.following_index then local row = handoffs[transit.sector_index]; row[transit.following_index] = (row[transit.following_index] or 0) + 1; total = total + 1 end
    end
    lines[#lines + 1] = 'HANDOFFS plan=final count=' .. total
    for a = 1, #sectors do for b = 1, #sectors do if handoffs[a][b] then lines[#lines + 1] = 'HANDOFF ' .. sectors[a].name .. ' ' .. sectors[b].name .. ' ' .. handoffs[a][b] end end end
    return lines
end
local function alert_lines(label, trajectories, conflicts)
    local last_by_pair, alerts = {}, {}
    for _, time in ipairs(times) do
        local observations = {}
        for _, name in ipairs(names) do
            local point, segment = trajectory.current_position(trajectories[name], time)
            if point then observations[name] = {point, segment} end
        end
        for i = 1, #names do
            local a = names[i]
            if observations[a] then
                for j = i + 1, #names do
                    local b = names[j]
                    if observations[b] then
                        local pa, sa, pb, sb = observations[a][1], observations[a][2], observations[b][1], observations[b][2]
                        local relative, velocity = {}, {}
                        for axis = 1, 3 do relative[axis], velocity[axis] = pa[axis] - pb[axis], sa.velocity[axis] - sb.velocity[axis] end
                        local loss = conflict.loss_interval(relative, velocity, 0.0, params.alert + 0.0, params.dh, params.dv)
                        if loss then
                            local key = a .. '-' .. b
                            local previous = last_by_pair[key]
                            if previous and time - previous.last == 60 then previous.last, previous.samples, previous.min_dist = time, previous.samples + 1, math.min(previous.min_dist, loss.distance)
                            else
                                local alert = {a = a, b = b, name = key, first = time, last = time, samples = 1, predicted = time + loss.lo, min_dist = loss.distance}
                                alerts[#alerts + 1], last_by_pair[key] = alert, alert
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(alerts, function(a, b) if a.first ~= b.first then return a.first < b.first end; if a.a ~= b.a then return a.a < b.a end; return a.b < b.b end)
    local detected, true_count, lead_sum, lines = {}, 0, 0.0, {'ALERTS plan=' .. label .. ' horizon=' .. params.alert .. ' count=' .. #alerts}
    for index, alert in ipairs(alerts) do
        for c, found in ipairs(conflicts) do
            if found.name == alert.name and found.start < alert.last + params.alert and found.finish > alert.first then
                detected[c] = true
                if alert.lead == nil then alert.lead = found.start - alert.first end
            end
        end
        local status = 'status=false lead=-'
        if alert.lead ~= nil then true_count, lead_sum = true_count + 1, lead_sum + alert.lead; status = 'status=true lead=' .. decimal(alert.lead) end
        lines[#lines + 1] = 'ALERT ' .. index .. ' ' .. alert.name .. ' first=' .. alert.first .. ' last=' .. alert.last .. ' samples=' .. alert.samples .. ' predicted=' .. decimal(alert.predicted) .. ' min_dist=' .. decimal(alert.min_dist) .. ' ' .. status
    end
    local missed = 0
    for c, found in ipairs(conflicts) do if not detected[c] then missed = missed + 1; lines[#lines + 1] = 'MISSED ' .. found.name .. ' start=' .. decimal(found.start) .. ' end=' .. decimal(found.finish) end end
    lines[#lines + 1] = 'SUMMARY alerts=' .. #alerts .. ' true=' .. true_count .. ' false=' .. (#alerts - true_count) .. ' missed=' .. missed .. ' mean_lead=' .. (true_count > 0 and decimal(lead_sum / true_count) or '-')
    return lines
end

local function radar_cell(point)
    local x0, y0, x1, y1, width, height = table.unpack(params.radar)
    local column = math.floor((10 * point[1] - x0) * width / (x1 - x0))
    local bottom_row = math.floor((10 * point[2] - y0) * height / (y1 - y0))
    if column >= 0 and column < width and bottom_row >= 0 and bottom_row < height then return {column, height - 1 - bottom_row} end
    return nil
end
local function new_grid(fill)
    local grid = {}
    for row = 1, params.radar[6] do grid[row] = {}; for column = 1, params.radar[5] do grid[row][column] = fill end end
    return grid
end
local function radar_snapshot(label, trajectories, conflicts, time)
    local grid, counts, owners, positions, in_flight = new_grid('.'), new_grid(0), new_grid(''), {}, {}
    for _, name in ipairs(names) do
        local point, segment = trajectory.current_position(trajectories[name], time)
        if point then
            local cell = radar_cell(point)
            positions[name] = {point = point, segment = segment, cell = cell}
            in_flight[#in_flight + 1] = name
            if cell then
                local column, row = cell[1] + 1, cell[2] + 1
                counts[row][column], owners[row][column] = counts[row][column] + 1, name
            end
        end
    end
    local current_conflicts, conflicted = active(conflicts, time), {}
    for _, found in ipairs(current_conflicts) do conflicted[found.a], conflicted[found.b] = true, true end
    for row = 1, #grid do
        for column = 1, #grid[row] do
            local count = counts[row][column]
            if count >= 2 then grid[row][column] = tostring(count)
            elseif count == 1 then local name = owners[row][column]; local character = name:sub(1, 1); grid[row][column] = conflicted[name] and character:lower() or character end
        end
    end
    for _, name in ipairs(in_flight) do
        local predicted = trajectory.current_position(trajectories[name], time + params.leader)
        local cell = predicted and radar_cell(predicted) or nil
        if cell and grid[cell[2] + 1][cell[1] + 1] == '.' then grid[cell[2] + 1][cell[1] + 1] = '*' end
    end
    local rows, lines = {}, {'RADAR plan=' .. label .. ' t=' .. time .. ' aircraft=' .. #in_flight .. ' conflicts=' .. #current_conflicts}
    for _, row in ipairs(grid) do rows[#rows + 1] = table.concat(row) end
    append(lines, report.chart(rows))
    for _, name in ipairs(in_flight) do
        local entry = positions[name]
        local point, segment, cell = entry.point, entry.segment, entry.cell
        lines[#lines + 1] = name .. ' x=' .. decimal(point[1]) .. ' y=' .. decimal(point[2]) .. ' fl=' .. decimal(point[3] / 100, 2) .. ' track=' .. decimal(track(segment), 1) .. ' phase=' .. segment.phase .. ' cell=' .. (cell and cell[1] .. ',' .. cell[2] or 'outside')
    end
    for _, found in ipairs(current_conflicts) do
        local a, b = positions[found.a].point, positions[found.b].point
        local dx, dy = a[1] - b[1], a[2] - b[2]
        lines[#lines + 1] = 'CONFLICT ' .. found.name .. ' dist=' .. decimal(math.sqrt(dx * dx + dy * dy)) .. ' vert=' .. decimal(math.abs(a[3] - b[3]), 1)
    end
    return lines
end
local function density_lines(label, trajectories)
    local density, maximum_count = new_grid(0), 0
    for _, time in ipairs(times) do
        for _, name in ipairs(names) do
            local point = trajectory.current_position(trajectories[name], time)
            local cell = point and radar_cell(point) or nil
            if cell then local row, column = cell[2] + 1, cell[1] + 1; density[row][column] = density[row][column] + 1 end
        end
    end
    local rows = {}
    for _, row in ipairs(density) do
        local cells = {}
        for _, count in ipairs(row) do maximum_count = math.max(maximum_count, count); cells[#cells + 1] = count == 0 and '.' or count < 10 and tostring(count) or '#' end
        rows[#rows + 1] = table.concat(cells)
    end
    local lines = {'DENSITY plan=' .. label .. ' from=' .. params.sample_start .. ' to=' .. params.sample_end .. ' step=60 max=' .. maximum_count}
    append(lines, report.chart(rows))
    return lines
end
local function flight_strips()
    local lines = {}
    for _, name in ipairs(names) do
        local plan, old, new = final[name], initial_trajectories[name], final_trajectories[name]
        lines[#lines + 1] = 'STRIP ' .. name .. ' type=' .. plan.type .. ' waypoints=' .. #plan.waypoints .. ' length=' .. decimal(new.length) .. ' manoeuvres=' .. (#plan.history > 0 and table.concat(plan.history, ',') or '-')
        for i, waypoint in ipairs(plan.waypoints) do
            local before, after = old.waypoint_times[i], new.waypoint_times[i]
            lines[#lines + 1] = 'WPT ' .. (i - 1) .. ' at=' .. waypoint.x .. ':' .. waypoint.y .. ' eta=' .. decimal(before[1]) .. '->' .. decimal(after[1]) .. ' fl=' .. before[2] .. '->' .. after[2]
        end
        local transits = {}
        for _, transit in ipairs(final_transits) do if transit.callsign == name then transits[#transits + 1] = transit.sector .. '@' .. decimal(transit.entry) end end
        lines[#lines + 1] = 'SECTORS ' .. (#transits > 0 and table.concat(transits, ',') or '-')
    end
    return lines
end
local conflicts_output = conflict_lines('initial', initial_conflicts, initial_trajectories)
append(conflicts_output, conflict_lines('final', final_conflicts, final_trajectories))
local alerts_output = alert_lines('initial', initial_trajectories, initial_conflicts)
append(alerts_output, alert_lines('final', final_trajectories, final_conflicts))
local radar_output = {}
for _, time in ipairs(params.snapshots) do append(radar_output, radar_snapshot('initial', initial_trajectories, initial_conflicts, time)); append(radar_output, radar_snapshot('final', final_trajectories, final_conflicts, time)) end
append(radar_output, density_lines('initial', initial_trajectories)); append(radar_output, density_lines('final', final_trajectories))
report.write_lines('trajectories.csv', trajectories_csv())
report.write_lines('conflicts.txt', conflicts_output)
report.write_lines('resolutions.txt', resolution_lines())
report.write_lines('sector_transits.csv', transit_lines())
report.write_lines('sector_load.csv', sector_load_lines())
report.write_lines('sector_report.txt', sector_report())
report.write_lines('alerts.txt', alerts_output)
report.write_lines('radar.txt', radar_output)
report.write_lines('strips.txt', flight_strips())
