local waveform_io = require("waveform_io")
local picker = require("picker")
local associator = require("associator")
local locator = require("locator")
local magnitude = require("magnitude")
local stations, params = waveform_io.read()
local function append(target, values)
    for _, value in ipairs(values) do
        target[#target + 1] = value
    end
end
local function sum(values)
    local result = 0.0
    for _, value in ipairs(values) do
        result = result + value
    end
    return result
end
local function scaled(value, digits)
    local factor = 1
    for _ = 1, digits do
        factor = factor * 10
    end
    local result = math.floor(math.abs(value) * factor + 0.5)
    return value < 0.0 and -result or result
end
local function decimal(value, digits)
    local factor = 1
    for _ = 1, digits do
        factor = factor * 10
    end
    local rounded = scaled(value, digits)
    local absolute = math.abs(rounded)
    local fraction = tostring(absolute % factor)
    local sign = rounded < 0 and "-" or ""
    return sign .. absolute // factor .. "." .. string.rep("0", digits - #fraction) .. fraction
end
local function time_text(sample)
    local fraction = tostring(sample % 100)
    return sample // 100 .. "." .. string.rep("0", 2 - #fraction) .. fraction
end
local function optional(value, digits)
    return value == nil and "-" or decimal(value, digits)
end
local function yes_no(value)
    return value and "yes" or "no"
end
local picks = {}
for ordinal, station in ipairs(stations) do
    append(picks, picker.detect(station, ordinal, params))
end
for index, pick in ipairs(picks) do
    pick.sequence = index
end
table.sort(picks, function(a, b)
    if a.sample ~= b.sample then
        return a.sample < b.sample
    elseif a.station ~= b.station then
        return a.station < b.station
    end
    return a.sequence < b.sequence
end)
local candidates = associator.associate(picks, params.association_window, params.min_stations)
local function station_ordered(indices)
    local result = {table.unpack(indices)}
    table.sort(result, function(a, b) return picks[a].station < picks[b].station end)
    return result
end
local function observations(indices, corrections)
    local result = {}
    for _, index in ipairs(indices) do
        local pick = picks[index]
        result[#result + 1] = {station = stations[pick.station], time = pick.time - (corrections and corrections[pick.station] or 0.0)}
    end
    return result
end
local events = {}
for _, candidate in ipairs(candidates) do
    local ordered = station_ordered(candidate.picks)
    local first = locator.run(observations(ordered), params)
    candidate.passes[1] = {picks = ordered, run = first}
    local retained = {}
    for index, current in ipairs(ordered) do
        local residual = first.residuals[index]
        if math.abs(residual) > params.residual_limit then
            candidate.dropped[#candidate.dropped + 1] = {pick = current, residual = residual}
        else
            retained[#retained + 1] = current
        end
    end
    candidate.remaining = #retained
    if #candidate.dropped > 0 and #retained < params.min_stations then
        candidate.rejected = true
        for _, current in ipairs(ordered) do
            picks[current].state = "rejected"
        end
    else
        local adopted = first
        if #candidate.dropped > 0 then
            adopted = locator.run(observations(retained), params)
            candidate.passes[2] = {picks = retained, run = adopted}
        end
        local number = #events + 1
        candidate.event = number
        for index, current in ipairs(retained) do
            local pick = picks[current]
            pick.state, pick.event, pick.first_residual = "used", number, adopted.residuals[index]
        end
        for _, item in ipairs(candidate.dropped) do
            picks[item.pick].state, picks[item.pick].event = "dropped", number
        end
        events[number] = {number = number, used = retained, first = adopted}
    end
end
local before_by_station, after_by_station, magnitude_by_station = {}, {}, {}
for ordinal = 1, #stations do
    before_by_station[ordinal], after_by_station[ordinal], magnitude_by_station[ordinal] = {}, {}, {}
end
for _, event in ipairs(events) do
    for _, current in ipairs(event.used) do
        local pick = picks[current]
        local values = before_by_station[pick.station]
        values[#values + 1] = pick.first_residual
    end
end
local corrections = {}
for ordinal, values in ipairs(before_by_station) do
    corrections[ordinal] = #values > 0 and sum(values) / #values or 0.0
end
local function quality(event)
    local solution, used, obs = event.final.solution, event.used, event.observations
    local result = locator.ellipse(solution, obs, params.velocity)
    local angles, nearest = {}, math.huge
    for _, current in ipairs(used) do
        local station = stations[picks[current].station]
        local dx, dy = station.x - solution[1], station.y - solution[2]
        local angle = locator.atan2(dx, dy) * 180.0 / locator.pi
        angles[#angles + 1] = angle < 0.0 and angle + 360.0 or angle
        nearest = math.min(nearest, math.sqrt(dx * dx + dy * dy))
    end
    table.sort(angles)
    local gap = angles[1] + 360.0 - angles[#angles]
    for index = 1, #angles - 1 do
        gap = math.max(gap, angles[index + 1] - angles[index])
    end
    local function fits(limits)
        return gap <= limits[1] and event.final.rms <= limits[2] and result.smaj <= limits[3]
    end
    result.grade = fits(params.quality_a) and "A" or fits(params.quality_b) and "B" or "C"
    result.gap, result.dmin = gap, nearest
    local dx, dy = solution[1] - event.first.solution[1], solution[2] - event.first.solution[2]
    result.dh, result.dz = math.sqrt(dx * dx + dy * dy), solution[3] - event.first.solution[3]
    result.jackknife, result.maximum = {}, nil
    for removed, current in ipairs(used) do
        local remaining = {}
        for index, observation in ipairs(obs) do
            if index ~= removed then
                remaining[#remaining + 1] = observation
            end
        end
        local run = locator.geiger(solution, remaining, params.velocity)
        local dx_j, dy_j, dz_j = run.solution[1] - solution[1], run.solution[2] - solution[2], run.solution[3] - solution[3]
        local record = {station = picks[current].station, dx = dx_j, dy = dy_j, dz = dz_j, shift = math.sqrt(dx_j * dx_j + dy_j * dy_j)}
        result.jackknife[#result.jackknife + 1] = record
        if not result.maximum or record.shift > result.maximum.shift then
            result.maximum = record
        end
    end
    return result
end
for _, event in ipairs(events) do
    event.observations = observations(event.used, corrections)
    event.start_rms = locator.rms(event.first.solution, event.observations, params.velocity)
    event.final = locator.geiger(event.first.solution, event.observations, params.velocity)
    event.solution = event.final.solution
    for index, current in ipairs(event.used) do
        local pick = picks[current]
        pick.residual = event.final.residuals[index]
        local values = after_by_station[pick.station]
        values[#values + 1] = pick.residual
    end
    event.quality = quality(event)
end
local all_local, relation_x, relation_y = {}, {}, {}
for _, event in ipairs(events) do
    local local_values, duration_values = {}, {}
    event.magnitudes = {}
    for _, current in ipairs(event.used) do
        local pick = picks[current]
        local radius = locator.distance(event.solution, stations[pick.station]) / 1000.0
        local record = magnitude.per_pick(pick, radius, params)
        record.pick = current
        event.magnitudes[#event.magnitudes + 1] = record
        duration_values[#duration_values + 1] = record.md
        if record.ml ~= nil then
            local_values[#local_values + 1] = record.ml
        end
    end
    event.ml = #local_values > 0 and magnitude.median(local_values) or nil
    event.md = magnitude.median(duration_values)
    if event.ml ~= nil then
        all_local[#all_local + 1] = event.ml
        relation_x[#relation_x + 1], relation_y[#relation_y + 1] = event.md, event.ml
    end
    for _, record in ipairs(event.magnitudes) do
        if record.ml ~= nil then
            local values = magnitude_by_station[picks[record.pick].station]
            values[#values + 1] = record.ml - event.ml
        end
    end
end
local magnitude_corrections = {}
for ordinal, values in ipairs(magnitude_by_station) do
    magnitude_corrections[ordinal] = #values > 0 and sum(values) / #values or 0.0
end
for _, event in ipairs(events) do
    local corrected = {}
    for _, record in ipairs(event.magnitudes) do
        if record.ml ~= nil then
            corrected[#corrected + 1] = record.ml - magnitude_corrections[picks[record.pick].station]
        end
    end
    event.mlc = #corrected > 0 and magnitude.median(corrected) or nil
end
local points, sd, st, sdd, sdt = {}, 0.0, 0.0, 0.0, 0.0
for _, event in ipairs(events) do
    for _, current in ipairs(event.used) do
        local pick = picks[current]
        local distance = locator.distance(event.solution, stations[pick.station]) / 1000.0
        local travel = pick.time - event.solution[4]
        points[#points + 1] = {distance, travel}
        sd, st = sd + distance, st + travel
        sdd, sdt = sdd + distance * distance, sdt + distance * travel
    end
end
local slope = (#points * sdt - sd * st) / (#points * sdd - sd * sd)
local intercept = (st - slope * sd) / #points
local error_sum = 0.0
for _, point in ipairs(points) do
    local residual = point[2] - intercept - slope * point[1]
    error_sum = error_sum + residual * residual
end
local regression = {count = #points, velocity = 1000.0 / slope, intercept = intercept, rms = math.sqrt(error_sum / #points)}
local clusters, visited = {}, {}
for initial = 1, #events do
    if not visited[initial] then
        local queue, members, cursor = {initial}, {}, 1
        visited[initial] = true
        while cursor <= #queue do
            local index = queue[cursor]
            cursor = cursor + 1
            members[#members + 1] = index
            local first = events[index].solution
            for other = 1, #events do
                if not visited[other] then
                    local second = events[other].solution
                    local dx, dy, dz = first[1] - second[1], first[2] - second[2], first[3] - second[3]
                    if math.abs(first[4] - second[4]) <= params.cluster[2] and math.sqrt((dx * dx + dy * dy) + dz * dz) <= params.cluster[1] then
                        visited[other], queue[#queue + 1] = true, other
                    end
                end
            end
        end
        table.sort(members)
        local center, low_time, high_time = {0.0, 0.0, 0.0}, math.huge, -math.huge
        for _, index in ipairs(members) do
            local event = events[index]
            event.cluster = #clusters + 1
            for axis = 1, 3 do
                center[axis] = center[axis] + event.solution[axis]
            end
            low_time, high_time = math.min(low_time, event.solution[4]), math.max(high_time, event.solution[4])
        end
        for axis = 1, 3 do
            center[axis] = center[axis] / #members
        end
        clusters[#clusters + 1] = {members = members, center = center, span = high_time - low_time}
    end
end
local station_sets, added = {}, {}
for number, event in ipairs(events) do
    station_sets[number] = {}
    for _, current in ipairs(event.used) do
        station_sets[number][picks[current].station] = true
    end
end
for index, pick in ipairs(picks) do
    if pick.state == "unassociated" then
        local best, best_error = nil, nil
        for number, event in ipairs(events) do
            if not station_sets[number][pick.station] then
                local residual = pick.time - event.solution[4] - locator.distance(event.solution, stations[pick.station]) / params.velocity - corrections[pick.station]
                if math.abs(residual) <= params.residual_limit and (not best or math.abs(residual) < math.abs(best_error)) then
                    best, best_error = number, residual
                end
            end
        end
        if best then
            pick.state, pick.event, pick.residual = "added", best, best_error
            station_sets[best][pick.station], added[#added + 1] = true, index
        end
    end
end
local frequency = magnitude.frequency(all_local)
local xm, ym = sum(relation_x) / #relation_x, sum(relation_y) / #relation_y
local xx, xy, yy = 0.0, 0.0, 0.0
for index, value in ipairs(relation_x) do
    local dx, dy = value - xm, relation_y[index] - ym
    xx, xy, yy = xx + dx * dx, xy + dx * dy, yy + dy * dy
end
local relation_slope = xy / xx
local relation = {count = #relation_x, slope = relation_slope, intercept = ym - relation_slope * xm,
    r = xy / math.sqrt(xx * yy), difference = ym - xm}
local function solution_text(heading, solution, rms, iteration)
    local prefix = heading .. (iteration and " " .. iteration or "")
    return prefix .. " x=" .. decimal(solution[1], 1) .. " y=" .. decimal(solution[2], 1) .. " z=" .. decimal(solution[3], 1) ..
        " t0=" .. decimal(solution[4], 3) .. " rms=" .. decimal(rms, 4)
end
local function pass_lines(number, indices, run)
    local codes, profile, result = {}, {}, {}
    for _, current in ipairs(indices) do
        codes[#codes + 1] = stations[picks[current].station].code
    end
    result[#result + 1] = "PASS " .. number .. " stations=" .. table.concat(codes, ",")
    result[#result + 1] = solution_text("GRID", run.grid.solution, run.grid.rms)
    for _, value in ipairs(run.grid.profile) do
        profile[#profile + 1] = decimal(value, 4)
    end
    result[#result + 1] = "PROFILE " .. table.concat(profile, " ")
    for _, record in ipairs(run.trace) do
        result[#result + 1] = solution_text("ITER", record.solution, record.rms, record.number)
    end
    for index, current in ipairs(indices) do
        local pick = picks[current]
        local station = stations[pick.station]
        local distance = locator.distance(run.solution, station)
        result[#result + 1] = "RES " .. station.code .. " dist=" .. decimal(distance, 1) .. " tt=" .. decimal(distance / params.velocity, 4) ..
            " obs=" .. time_text(pick.sample) .. " res=" .. decimal(run.residuals[index], 4)
    end
    return result
end
local function location_lines()
    local result = {}
    for _, candidate in ipairs(candidates) do
        result[#result + 1] = "CANDIDATE " .. candidate.number .. " picks=" .. #candidate.picks .. " first=" .. time_text(picks[candidate.first].sample)
        append(result, pass_lines(1, candidate.passes[1].picks, candidate.passes[1].run))
        for _, record in ipairs(candidate.dropped) do
            result[#result + 1] = "DROP " .. stations[picks[record.pick].station].code .. " res=" .. decimal(record.residual, 4)
        end
        if candidate.rejected then
            result[#result + 1] = "RESULT REJECTED stations=" .. candidate.remaining
        else
            if candidate.passes[2] then
                append(result, pass_lines(2, candidate.passes[2].picks, candidate.passes[2].run))
            end
            result[#result + 1] = "RESULT EVENT " .. candidate.event
        end
    end
    result[#result + 1] = "CORRECTIONS"
    for ordinal, station in ipairs(stations) do
        result[#result + 1] = station.code .. " n=" .. #before_by_station[ordinal] .. " correction=" .. decimal(corrections[ordinal], 4)
    end
    local depths, rms_values, grades = {}, {}, {A = 0, B = 0, C = 0}
    for _, event in ipairs(events) do
        local q = event.quality
        result[#result + 1] = "EVENT " .. event.number
        result[#result + 1] = solution_text("START", event.first.solution, event.start_rms)
        for _, record in ipairs(event.final.trace) do
            result[#result + 1] = solution_text("ITER", record.solution, record.rms, record.number)
        end
        for index, current in ipairs(event.used) do
            local pick = picks[current]
            local station = stations[pick.station]
            local distance = locator.distance(event.solution, station)
            result[#result + 1] = "RES " .. station.code .. " dist=" .. decimal(distance, 1) .. " tt=" .. decimal(distance / params.velocity, 4) ..
                " obs=" .. time_text(pick.sample) .. " corr=" .. decimal(corrections[pick.station], 4) .. " res=" .. decimal(event.final.residuals[index], 4)
        end
        append(result, {
            "ELLIPSE smaj=" .. decimal(q.smaj, 1) .. " smin=" .. decimal(q.smin, 1) .. " az=" .. decimal(q.az, 1) .. " erz=" .. decimal(q.erz, 1) .. " ert=" .. decimal(q.ert, 4),
            "SHIFT dh=" .. decimal(q.dh, 1) .. " dz=" .. decimal(q.dz, 1),
            "GAP " .. decimal(q.gap, 1) .. " DMIN " .. decimal(q.dmin, 1) .. " QUALITY " .. q.grade
        })
        for _, jack in ipairs(q.jackknife) do
            result[#result + 1] = "JACK " .. stations[jack.station].code .. " dx=" .. decimal(jack.dx, 1) .. " dy=" .. decimal(jack.dy, 1) ..
                " dz=" .. decimal(jack.dz, 1) .. " shift=" .. decimal(jack.shift, 1)
        end
        result[#result + 1] = "JACKKNIFE max=" .. decimal(q.maximum.shift, 1) .. " station=" .. stations[q.maximum.station].code
        depths[#depths + 1], rms_values[#rms_values + 1] = event.solution[3], event.final.rms
        grades[q.grade] = grades[q.grade] + 1
    end
    result[#result + 1] = "FIT n=" .. regression.count .. " velocity=" .. decimal(regression.velocity, 1) .. " intercept=" .. decimal(regression.intercept, 4) .. " rms=" .. decimal(regression.rms, 4)
    for number, cluster in ipairs(clusters) do
        if #cluster.members >= 2 then
            local members = {}
            for _, value in ipairs(cluster.members) do
                members[#members + 1] = tostring(value)
            end
            result[#result + 1] = "CLUSTER " .. number .. " events=" .. table.concat(members, ",") .. " x=" .. decimal(cluster.center[1], 1) ..
                " y=" .. decimal(cluster.center[2], 1) .. " z=" .. decimal(cluster.center[3], 1) .. " span=" .. decimal(cluster.span, 3)
        end
    end
    result[#result + 1] = "ADDED"
    for _, current in ipairs(added) do
        local pick = picks[current]
        result[#result + 1] = stations[pick.station].code .. " sample=" .. pick.sample .. " event=" .. pick.event .. " res=" .. decimal(pick.residual, 4)
    end
    local rejected, unassociated = 0, 0
    for _, candidate in ipairs(candidates) do
        rejected = rejected + (candidate.rejected and 1 or 0)
    end
    for _, pick in ipairs(picks) do
        unassociated = unassociated + (pick.state == "unassociated" and 1 or 0)
    end
    table.sort(depths)
    append(result, {
        "SUMMARY picks=" .. #picks .. " candidates=" .. #candidates .. " events=" .. #events .. " rejected=" .. rejected .. " unassociated=" .. unassociated,
        "DEPTH min=" .. decimal(depths[1], 1) .. " median=" .. decimal(magnitude.median(depths), 1) .. " max=" .. decimal(depths[#depths], 1),
        "QUALITY A=" .. grades.A .. " B=" .. grades.B .. " C=" .. grades.C .. " mean_rms=" .. decimal(sum(rms_values) / #events, 4)
    })
    return result
end
local function picks_lines()
    local result = {"station,sample,time_s,duration,snr,amplitude,clipped,event,status,residual"}
    for _, pick in ipairs(picks) do
        local residual = (pick.state == "used" or pick.state == "added") and decimal(pick.residual, 4) or "-"
        result[#result + 1] = table.concat({stations[pick.station].code, pick.sample, time_text(pick.sample), pick.duration,
            decimal(pick.ratio, 2), pick.amplitude, yes_no(pick.clipped), pick.event, pick.state, residual}, ",")
    end
    return result
end
local function catalog_lines()
    local result = {"event,origin_time,x,y,depth,rms,stations,gap,dmin,smaj,smin,azimuth,erz,ml,md,quality,cluster"}
    for _, event in ipairs(events) do
        local q, s = event.quality, event.solution
        result[#result + 1] = table.concat({event.number, decimal(s[4], 3), decimal(s[1], 1), decimal(s[2], 1), decimal(s[3], 1),
            decimal(event.final.rms, 4), #event.used, decimal(q.gap, 1), decimal(q.dmin, 1), decimal(q.smaj, 1), decimal(q.smin, 1),
            decimal(q.az, 1), decimal(q.erz, 1), optional(event.ml, 2), decimal(event.md, 2), q.grade, event.cluster}, ",")
    end
    return result
end
local function grid(width, height)
    local result = {}
    for row = 1, height do
        result[row] = {}
        for column = 1, width do
            result[row][column] = " "
        end
    end
    return result
end
local function chart_lines(canvas, width)
    local frame = "+" .. string.rep("-", width) .. "+"
    local result = {frame}
    for _, row in ipairs(canvas) do
        result[#result + 1] = "|" .. table.concat(row) .. "|"
    end
    result[#result + 1] = frame
    return result
end
local function timeline_lines()
    local duration, width, low, high, height = table.unpack(params.timeline)
    local canvas = grid(width, height)
    for _, event in ipairs(events) do
        if event.ml ~= nil then
            local time, h = scaled(event.solution[4], 3), scaled(event.ml, 2)
            if time >= 0 and time < 1000 * duration and h >= 100 * low then
                local column = time * width // (1000 * duration)
                local level = math.min((h - 100 * low) * height // (100 * (high - low)), height - 1)
                for k = 0, level do
                    local row = height - k
                    if k == level then
                        canvas[row][column + 1] = "o"
                    elseif canvas[row][column + 1] == " " then
                        canvas[row][column + 1] = "|"
                    end
                end
            end
        end
    end
    local result = {"TIMELINE t=0.." .. duration .. " ML=" .. low .. ".." .. high}
    append(result, chart_lines(canvas, width))
    return result
end
local function magnitude_lines()
    local result = {}
    for _, event in ipairs(events) do
        local count = 0
        for _, record in ipairs(event.magnitudes) do
            count = count + (record.ml ~= nil and 1 or 0)
        end
        result[#result + 1] = "EVENT " .. event.number .. " ML=" .. optional(event.ml, 2) .. " n=" .. count .. " MD=" .. decimal(event.md, 2)
        for _, record in ipairs(event.magnitudes) do
            local pick = picks[record.pick]
            local line = stations[pick.station].code .. " r=" .. decimal(record.r, 3) .. " amp=" .. pick.amplitude .. " "
            if record.ml == nil then
                line = line .. "clipped"
            else
                line = line .. "ml=" .. decimal(record.ml, 2) .. " res=" .. decimal(record.ml - event.ml, 2)
            end
            result[#result + 1] = line .. " dur=" .. pick.duration .. " md=" .. decimal(record.md, 2)
        end
    end
    result[#result + 1] = "CORRECTED"
    for _, event in ipairs(events) do
        result[#result + 1] = "EVENT " .. event.number .. " MLC=" .. optional(event.mlc, 2)
    end
    result[#result + 1] = "FMD"
    for class = frequency.low, frequency.high do
        local cumulative = 0
        for other = class, frequency.high do
            cumulative = cumulative + (frequency.counts[other] or 0)
        end
        result[#result + 1] = "M=" .. magnitude.class_text(class) .. " N=" .. (frequency.counts[class] or 0) .. " CUM=" .. cumulative
    end
    append(result, {
        "MC " .. magnitude.class_text(frequency.completeness),
        "BVALUE " .. decimal(frequency.b, 3) .. " SIGMA " .. decimal(frequency.sigma, 3) .. " N " .. frequency.n,
        "AVALUE " .. decimal(frequency.a, 3),
        "MLMD n=" .. relation.count .. " slope=" .. decimal(relation.slope, 3) .. " intercept=" .. decimal(relation.intercept, 3) ..
            " r=" .. decimal(relation.r, 3) .. " mean_diff=" .. decimal(relation.difference, 3)
    })
    append(result, timeline_lines())
    return result
end
local function residual_rms(values)
    local total = 0.0
    for _, value in ipairs(values) do
        total = total + value * value
    end
    return math.sqrt(total / #values)
end
local function station_lines()
    local result = {}
    for ordinal, station in ipairs(stations) do
        local counts = {used = 0, dropped = 0, added = 0, rejected = 0, unassociated = 0}
        for _, pick in ipairs(picks) do
            if pick.station == ordinal then
                counts[pick.state] = counts[pick.state] + 1
            end
        end
        local before, after = "-", "-"
        if #before_by_station[ordinal] > 0 then
            before = decimal(residual_rms(before_by_station[ordinal]), 4)
            after = decimal(residual_rms(after_by_station[ordinal]), 4)
        end
        local stats = station.statistics
        append(result, {
            "STATION " .. station.code .. " x=" .. station.x .. " y=" .. station.y .. " elevation=" .. station.elevation,
            "SAMPLES start=" .. station.start .. " count=" .. #station.samples .. " mean=" .. stats.mean .. " noise=" .. decimal(stats.noise, 1) .. " peak=" .. stats.peak .. " clipped=" .. stats.clipped,
            "TRIGGERS total=" .. stats.triggers .. " short=" .. stats.short .. " picks=" .. stats.picks,
            "PICKS used=" .. counts.used .. " dropped=" .. counts.dropped .. " added=" .. counts.added .. " rejected=" .. counts.rejected .. " unassociated=" .. counts.unassociated,
            "RESIDUALS n=" .. #before_by_station[ordinal] .. " rms=" .. before .. " correction=" .. decimal(corrections[ordinal], 4) .. " after=" .. after,
            "MAGNITUDES n=" .. #magnitude_by_station[ordinal] .. " correction=" .. decimal(magnitude_corrections[ordinal], 2)
        })
    end
    return result
end
local function symbol(event)
    if event.ml == nil then
        return "?"
    end
    local h = scaled(event.ml, 2)
    return h < 100 and "." or h < 200 and "o" or h < 300 and "O" or "@"
end
local function plotted_positions(event)
    local x, y, z = scaled(event.solution[1], 1), scaled(event.solution[2], 1), scaled(event.solution[3], 1)
    local left, right, bottom, top = table.unpack(params.map_area)
    local width, map_height = table.unpack(params.map_size)
    local depth_limit, section_height = table.unpack(params.section)
    local map_position, ew_position, ns_position = nil, nil, nil
    if x >= 10 * left and x < 10 * right and y >= 10 * bottom and y < 10 * top then
        map_position = {(x - 10 * left) * width // (10 * (right - left)), map_height - 1 - (y - 10 * bottom) * map_height // (10 * (top - bottom))}
    end
    if x >= 10 * left and x < 10 * right and z < 10 * depth_limit then
        ew_position = {(x - 10 * left) * width // (10 * (right - left)), z * section_height // (10 * depth_limit)}
    end
    if y >= 10 * bottom and y < 10 * top and z < 10 * depth_limit then
        ns_position = {(y - 10 * bottom) * width // (10 * (top - bottom)), z * section_height // (10 * depth_limit)}
    end
    return {map_position = map_position, ew_position = ew_position, ns_position = ns_position}
end
local function station_position(station)
    local left, right, bottom, top = table.unpack(params.map_area)
    local width, height = table.unpack(params.map_size)
    if station.x < left or station.x >= right or station.y < bottom or station.y >= top then
        return nil
    end
    return {(station.x - left) * width // (right - left), height - 1 - (station.y - bottom) * height // (top - bottom)}
end
local function position_text(position)
    return position and position[1] .. "," .. position[2] or "outside"
end
local function place(canvas, position, mark)
    if not position then
        return
    end
    local ranks = {[" "] = -1, ["?"] = 0, ["."] = 1, o = 2, O = 3, ["@"] = 4, ["^"] = 5}
    local column, row = position[1] + 1, position[2] + 1
    if ranks[mark] > ranks[canvas[row][column]] then
        canvas[row][column] = mark
    end
end
local function map_lines()
    local left, right, bottom, top = table.unpack(params.map_area)
    local width, height = table.unpack(params.map_size)
    local depth_limit, section_height = table.unpack(params.section)
    local canvas = {grid(width, height), grid(width, section_height), grid(width, section_height)}
    local positions, station_positions = {}, {}
    for number, event in ipairs(events) do
        local point = plotted_positions(event)
        positions[number] = point
        local mark = symbol(event)
        place(canvas[1], point.map_position, mark)
        place(canvas[2], point.ew_position, mark)
        place(canvas[3], point.ns_position, mark)
    end
    for ordinal, station in ipairs(stations) do
        local point = station_position(station)
        station_positions[ordinal] = point
        place(canvas[1], point, "^")
    end
    local titles = {"MAP x=" .. left .. ".." .. right .. " y=" .. bottom .. ".." .. top,
        "SECTION EW x=" .. left .. ".." .. right .. " z=0.." .. depth_limit,
        "SECTION NS y=" .. bottom .. ".." .. top .. " z=0.." .. depth_limit}
    local result = {}
    for index, title in ipairs(titles) do
        result[#result + 1] = title
        append(result, chart_lines(canvas[index], width))
    end
    result[#result + 1] = "LEGEND ^ station . ML<1 o ML<2 O ML<3 @ ML>=3 ? no ML"
    for ordinal, station in ipairs(stations) do
        result[#result + 1] = "STATION " .. station.code .. " map=" .. position_text(station_positions[ordinal])
    end
    for number, event in ipairs(events) do
        local point = positions[number]
        result[#result + 1] = "EVENT " .. number .. " " .. symbol(event) .. " map=" .. position_text(point.map_position) ..
            " ew=" .. position_text(point.ew_position) .. " ns=" .. position_text(point.ns_position)
    end
    return result
end
local function save(name, values)
    local output = assert(io.open("output/" .. name, "w"))
    output:write(table.concat(values, "\n"), "\n")
    output:close()
end
save("picks.csv", picks_lines())
save("locations.txt", location_lines())
save("catalog.csv", catalog_lines())
save("magnitudes.txt", magnitude_lines())
save("stations.txt", station_lines())
save("map.txt", map_lines())
