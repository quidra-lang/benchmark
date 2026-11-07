local Matrix = require("matrix")
local Kalman = require("kalman")
local Association = require("association")
local IMM = require("imm")
local Evaluation = require("evaluation")
local filters = { "cv", "ca", "abg", "imm", "rts" }
local real, distance, squared_distance = Evaluation.real, Evaluation.distance, Evaluation.squared_distance
local function append(a, b) for _, value in ipairs(b) do a[#a + 1] = value end end
local function map(values, fn) local result = {}; for i, value in ipairs(values) do result[i] = fn(value, i) end; return result end
local function keys(values) local result = {}; for key in pairs(values) do result[#result + 1] = key end; table.sort(result); return result end
local function count(values) local result = 0; for _ in pairs(values) do result = result + 1 end; return result end
local function first_four(state) return { state[1], state[2], state[3], state[4] } end
local function optional(value) return value ~= nil and tostring(value) or "-" end
local function listed(keyword, values) return keyword .. " " .. (#values > 0 and table.concat(values, " ") or "none") end
local function words(line, separator)
    local result = {}
    for value in line:gmatch(separator or "%S+") do result[#result + 1] = value end
    return result
end
local function path_length(positions)
    local total = 0.0
    for i = 2, #positions do total = total + distance(positions[i - 1], positions[i]) end
    return total
end
local function rmse(errors) return math.sqrt(Matrix.total(errors) / #errors) end
local function groups(items)
    local result = {}
    for _, item in ipairs(items) do
        local last = result[#result]
        if last and last[2] + 1 == item[1] and last[3] == item[2] then last[2] = item[1] else result[#result + 1] = { item[1], item[1], item[2] } end
    end
    return result
end
local function filter_scores(values)
    local parts, best, smallest = {}, nil, nil
    for _, name in ipairs(filters) do
        local text = real(values[name])
        parts[#parts + 1] = name .. " " .. text
        local rounded = tonumber(text)
        if not best or rounded < smallest then best, smallest = name, rounded end
    end
    return table.concat(parts, " ") .. " best " .. best
end
local function framed(rows)
    local border = "+" .. string.rep("-", #rows[1]) .. "+"
    local lines = { border }
    for _, row in ipairs(rows) do lines[#lines + 1] = "|" .. table.concat(row) .. "|" end
    lines[#lines + 1] = border
    return lines
end
local A = {}
A.__index = A
function A.read()
    local self = setmetatable({ measurements = {}, times = {}, truth = {}, params = {}, tracks = {}, track_rows = { "track,scan,x,y,vx,vy,status" }, association_log = {},
        conflict_measurements = 0, conflict_tracks = 0, greedy_differences = 0 }, A)
    for _, kind in ipairs({ "measurements", "truth" }) do
        local input = assert(io.open("input/" .. kind .. ".csv", "r"))
        input:read("*l")
        for line in input:lines() do
            local values = words(line, "[^,]+")
            local point = { tonumber(values[3]), tonumber(values[4]) }
            if kind == "measurements" then
                local scan = tonumber(values[1])
                self.times[scan] = tonumber(values[2])
                if not self.measurements[scan] then self.measurements[scan] = {} end
                local measurements = self.measurements[scan]
                measurements[#measurements + 1] = point
            else
                local target, scan = tonumber(values[1]), tonumber(values[2])
                if not self.truth[target] then self.truth[target] = {} end
                self.truth[target][scan] = point
            end
        end
        input:close()
    end
    for line in io.lines("input/params.txt") do
        local values = words(line)
        local name = values[1]
        if name == "MODEL" then self.params[name] = values[2]
        else self.params[name] = {}; for i = 2, #values do self.params[name][i - 1] = tonumber(values[i]) end end
    end
    self.scans, self.targets, self.primary = #self.measurements, keys(self.truth), self.params.MODEL:lower()
    return self
end
function A:parameter(name) return self.params[name][1] end
function A:make_kalman(model, measurement)
    return Kalman.new(model, self:parameter("Q_" .. model), self:parameter("SIGMA"), self:parameter("INIT_VELOCITY_VARIANCE"), self:parameter("INIT_ACCELERATION_VARIANCE"), measurement)
end
function A:track_all_scans()
    local required, window = table.unpack(self.params.CONFIRM)
    for scan = 1, self.scans do
        local live = {}
        for _, track in ipairs(self.tracks) do if track.status ~= "deleted" then live[#live + 1] = track end end
        local measurements = self.measurements[scan]
        if scan > 1 then for _, track in ipairs(live) do track.kalman:predict(self.times[scan] - self.times[scan - 1]) end end
        local usable, innovations, row_gates, column_gates, candidates = {}, {}, {}, {}, {}
        for j = 1, #measurements do column_gates[j] = 0 end
        for row, track in ipairs(live) do
            usable[row], innovations[row], row_gates[row] = {}, {}, 0
            for column, measurement in ipairs(measurements) do
                local innovation = track.kalman:innovation(measurement)
                if innovation[4] <= self:parameter("GATE") then
                    usable[row][column], innovations[row][column] = innovation[4], innovation
                    row_gates[row], column_gates[column] = row_gates[row] + 1, column_gates[column] + 1
                    candidates[#candidates + 1] = { row, column }
                end
            end
        end
        local assigned = Association.optimal(#live, #measurements, usable)
        table.sort(candidates, function(a, b)
            local x, y = usable[a[1]][a[2]], usable[b[1]][b[2]]
            if x ~= y then return x < y end
            return live[a[1]].number < live[b[1]].number or live[a[1]].number == live[b[1]].number and a[2] < b[2]
        end)
        local greedy, used_rows, used_columns = {}, {}, {}
        for _, pair in ipairs(candidates) do
            if not used_rows[pair[1]] and not used_columns[pair[2]] then greedy[#greedy + 1], used_rows[pair[1]], used_columns[pair[2]] = pair, true, true end
        end
        table.sort(greedy, function(a, b) return a[1] < b[1] end)
        local equal = #assigned == #greedy
        if equal then for i, pair in ipairs(assigned) do if pair[1] ~= greedy[i][1] or pair[2] ~= greedy[i][2] then equal = false; break end end end
        if not equal then self.greedy_differences = self.greedy_differences + 1 end
        local matches, missed, confirmed, deleted = {}, {}, {}, {}
        used_columns = {}
        for _, pair in ipairs(assigned) do matches[pair[1]], used_columns[pair[2]] = pair[2], true end
        for row, track in ipairs(live) do
            local column = matches[row]
            if column then
                local measurement = measurements[column]
                track.kalman:update(measurement, innovations[row][column])
                track.observations[scan], track.nis[scan], track.last_hit = measurement, usable[row][column], scan
                track.hits, track.consecutive_misses = track.hits + 1, 0
            else
                track.observations[scan], track.consecutive_misses = false, track.consecutive_misses + 1
                missed[#missed + 1] = track.number
            end
            if track.status == "confirmed" then
                if track.consecutive_misses >= self:parameter("DELETE") then track.status, track.deleted = "deleted", scan; deleted[#deleted + 1] = track.number end
            elseif track.hits >= required then track.status, track.confirmed = "confirmed", scan; confirmed[#confirmed + 1] = track.number
            elseif scan - track.birth + 1 >= window then track.status, track.deleted = "deleted", scan; deleted[#deleted + 1] = track.number end
        end
        local new, processed = {}, {}
        append(processed, live)
        for column, measurement in ipairs(measurements) do
            if not used_columns[column] then
                local track = { number = #self.tracks + 1, birth = scan, last_hit = scan, status = "tentative", hits = 1, consecutive_misses = 0,
                    observations = { [scan] = measurement }, nis = {}, primary_matches = {}, kalman = self:make_kalman(self.params.MODEL, measurement) }
                self.tracks[#self.tracks + 1], processed[#processed + 1] = track, track
                new[#new + 1] = track.number .. ":" .. column
            end
        end
        local conflicts_m, conflicts_t, tentative_count, confirmed_count = 0, 0, 0, 0
        for _, count in ipairs(column_gates) do if count >= 2 then conflicts_m = conflicts_m + 1 end end
        for _, count in ipairs(row_gates) do if count >= 2 then conflicts_t = conflicts_t + 1 end end
        for _, track in ipairs(self.tracks) do if track.status == "tentative" then tentative_count = tentative_count + 1 elseif track.status == "confirmed" then confirmed_count = confirmed_count + 1 end end
        self.conflict_measurements, self.conflict_tracks = self.conflict_measurements + conflicts_m, self.conflict_tracks + conflicts_t
        local gates, assignment_text, greedy_text = {}, {}, {}
        for row, track in ipairs(live) do for column = 1, #measurements do if usable[row][column] ~= nil then gates[#gates + 1] = track.number .. ":" .. column .. "=" .. real(usable[row][column]) end end end
        for _, pair in ipairs(assigned) do assignment_text[#assignment_text + 1] = live[pair[1]].number .. ":" .. pair[2] end
        for _, pair in ipairs(greedy) do greedy_text[#greedy_text + 1] = live[pair[1]].number .. ":" .. pair[2] end
        append(self.association_log, {
            string.format("scan %d tracks %d measurements %d", scan, #live, #measurements), listed("gate", gates), listed("assign", assignment_text), listed("greedy", greedy_text),
            listed("missed", missed), listed("new", new), listed("confirmed", confirmed), listed("deleted", deleted),
            string.format("status tentative %d confirmed %d", tentative_count, confirmed_count), string.format("conflicts measurements %d tracks %d", conflicts_m, conflicts_t)
        })
        for _, track in ipairs(processed) do
            local row = { track.number, scan }
            append(row, map(first_four(track.kalman.x), real)); row[#row + 1] = track.status
            self.track_rows[#self.track_rows + 1] = table.concat(row, ",")
        end
    end
    self.evaluated = {}
    for _, track in ipairs(self.tracks) do if track.confirmed then self.evaluated[#self.evaluated + 1] = track end end
end
function A:abg_estimates(track)
    local alpha, beta, gamma = table.unpack(self.params.ABG)
    local first = track.observations[track.birth]
    local state, estimates = { first[1], first[2], 0.0, 0.0, 0.0, 0.0 }, {}
    for scan = track.birth, track.last_hit do
        if scan > track.birth then
            local interval, measurement = self.times[scan] - self.times[scan - 1], track.observations[scan]
            for axis = 1, 2 do
                local p, v, w = state[axis], state[axis + 2], state[axis + 4]
                p, v = p + interval * v + interval * interval * w / 2, v + interval * w
                if measurement then local residual = measurement[axis] - p; p, v, w = p + alpha * residual, v + beta * residual / interval, w + 2 * gamma * residual / (interval * interval) end
                state[axis], state[axis + 2], state[axis + 4] = p, v, w
            end
        end
        estimates[scan] = first_four(state)
    end
    return estimates
end
function A:compare_filters()
    for _, track in ipairs(self.evaluated) do
        track.span, track.estimates, track.model_logs = {}, {}, {}
        for scan = track.birth, track.last_hit do track.span[#track.span + 1] = scan end
        local histories = {}
        for _, name in ipairs({ "cv", "ca" }) do
            local kalman, history, likelihood = self:make_kalman(name:upper(), track.observations[track.birth]), {}, 0.0
            track.estimates[name] = {}
            for _, scan in ipairs(track.span) do
                if scan > track.birth then
                    kalman:predict(self.times[scan] - self.times[scan - 1])
                    if track.observations[scan] then local _, value = kalman:update(track.observations[scan]); likelihood = likelihood + value end
                end
                track.estimates[name][scan], history[#history + 1] = first_four(kalman.x), kalman:snapshot()
            end
            histories[name], track.model_logs[name] = history, likelihood
        end
        track.estimates.abg, track.estimates.rts, track.primary_covariances = self:abg_estimates(track), {}, {}
        local history = histories[self.primary]
        local smoothed = Kalman.smooth(history)
        for i, scan in ipairs(track.span) do track.primary_covariances[scan], track.estimates.rts[scan] = history[i].P, first_four(smoothed[i]) end
        local imm = IMM.new(self.params.IMM_Q, self.params.IMM_TRANSITION, self.params.IMM_INITIAL, self:parameter("SIGMA"), self:parameter("INIT_VELOCITY_VARIANCE"), track.observations[track.birth])
        track.high, track.estimates.imm, track.nis_values = {}, {}, {}
        local gap, longest = 0, 0
        for _, scan in ipairs(track.span) do
            if scan > track.birth then imm:step(self.times[scan] - self.times[scan - 1], track.observations[scan]) end
            track.estimates.imm[scan], track.high[scan] = imm:estimate(), imm.probabilities[2]
            if track.nis[scan] ~= nil then track.nis_values[#track.nis_values + 1] = track.nis[scan] end
            gap = not track.observations[scan] and gap + 1 or 0
            longest = math.max(longest, gap)
        end
        track.longest_gap, track.path = longest, path_length(map(track.span, function(scan) return track.estimates.rts[scan] end))
    end
end
function A:evaluate_scans()
    self.labels, self.ospa_values, self.scan_sizes, self.continuities = {}, {}, {}, {}
    for _, name in ipairs(filters) do
        self.labels[name], self.ospa_values[name], self.continuities[name] = {}, {}, {}
        for _, target in ipairs(self.targets) do self.labels[name][target] = {} end
    end
    for scan = 1, self.scans do
        local tracks, targets = {}, {}
        for _, track in ipairs(self.evaluated) do if scan >= track.birth and scan <= track.last_hit then tracks[#tracks + 1] = track end end
        for _, target in ipairs(self.targets) do if self.truth[target][scan] then targets[#targets + 1] = target end end
        self.scan_sizes[scan] = { #targets, #tracks }
        local positions = map(targets, function(target) return self.truth[target][scan] end)
        for _, name in ipairs(filters) do
            local estimates = map(tracks, function(track) return track.estimates[name][scan] end)
            local usable = {}
            for row, estimate in ipairs(estimates) do
                usable[row] = {}
                for column, point in ipairs(positions) do local value = distance(estimate, point); if value <= self:parameter("MATCH_DISTANCE") then usable[row][column] = value end end
            end
            for _, pair in ipairs(Association.optimal(#tracks, #targets, usable)) do
                local track, target = tracks[pair[1]], targets[pair[2]]
                self.labels[name][target][scan] = track.number
                if name == self.primary then track.primary_matches[scan] = target end
            end
            self.ospa_values[name][scan] = Evaluation.ospa(estimates, positions, self:parameter("OSPA_CUTOFF"))
        end
    end
    for _, name in ipairs(filters) do
        for _, target in ipairs(self.targets) do
            local values = map(keys(self.truth[target]), function(scan) return self.labels[name][target][scan] or false end)
            self.continuities[name][target] = Evaluation.continuity(values)
        end
    end
end
function A:match_tracks()
    local cutoff, usable, details = self:parameter("OSPA_CUTOFF"), {}, {}
    for row, track in ipairs(self.evaluated) do
        usable[row], details[row] = {}, {}
        for column, target in ipairs(self.targets) do
            local positions, scans = self.truth[target], keys(self.truth[target])
            local common, distances, allowed = {}, {}, false
            for _, scan in ipairs(track.span) do
                if positions[scan] then
                    common[#common + 1] = scan
                    distances[scan] = distance(track.estimates[self.primary][scan], positions[scan])
                    if distances[scan] < cutoff then allowed = true end
                end
            end
            if #common > 0 and allowed then
                local total, union_count = 0.0, 0
                for scan = math.min(track.birth, scans[1]), math.max(track.last_hit, scans[#scans]) do
                    if scan >= track.birth and scan <= track.last_hit or positions[scan] then
                        union_count, total = union_count + 1, total + (distances[scan] and math.min(cutoff, distances[scan]) or cutoff)
                    end
                end
                usable[row][column], details[row][column] = total / union_count, common
            end
        end
    end
    self.matched_tracks = {}
    for _, pair in ipairs(Association.optimal(#self.evaluated, #self.targets, usable)) do
        local row, column = pair[1], pair[2]
        local track, target = self.evaluated[row], self.targets[column]
        track.target, track.common, track.mean_distance, self.matched_tracks[target] = target, details[row][column], usable[row][column], track
    end
end
function A:evaluate_errors()
    self.target_results, self.overall_position, self.overall_velocity = {}, {}, {}
    local overall_position, overall_velocity = {}, {}
    for _, name in ipairs(filters) do overall_position[name], overall_velocity[name] = {}, {} end
    for _, target in ipairs(self.targets) do
        local track = self.matched_tracks[target]
        if track then
            local positions, velocities = self.truth[target], {}
            for _, scan in ipairs(track.common) do
                if positions[scan - 1] and positions[scan + 1] then
                    local interval = self.times[scan + 1] - self.times[scan - 1]
                    velocities[scan] = { (positions[scan + 1][1] - positions[scan - 1][1]) / interval, (positions[scan + 1][2] - positions[scan - 1][2]) / interval }
                end
            end
            local result = { track = track, position = {}, velocity = {}, velocity_count = count(velocities), nees = {} }
            for _, name in ipairs(filters) do
                local position_errors, velocity_errors = {}, {}
                for _, scan in ipairs(track.common) do position_errors[#position_errors + 1] = squared_distance(track.estimates[name][scan], positions[scan]) end
                for _, scan in ipairs(keys(velocities)) do local state = track.estimates[name][scan]; velocity_errors[#velocity_errors + 1] = squared_distance({ state[3], state[4] }, velocities[scan]) end
                result.position[name], result.velocity[name] = rmse(position_errors), rmse(velocity_errors)
                append(overall_position[name], position_errors); append(overall_velocity[name], velocity_errors)
            end
            for _, scan in ipairs(track.common) do
                local estimate, covariance = track.estimates[self.primary][scan], track.primary_covariances[scan]
                local error_value = { estimate[1] - positions[scan][1], estimate[2] - positions[scan][2] }
                local p2 = { { covariance[1][1], covariance[1][2] }, { covariance[2][1], covariance[2][2] } }
                result.nees[#result.nees + 1] = Matrix.quadratic2(error_value, Matrix.inverse(p2))
            end
            self.target_results[target] = result
        end
    end
    for _, name in ipairs(filters) do self.overall_position[name], self.overall_velocity[name] = rmse(overall_position[name]), rmse(overall_velocity[name]) end
end
function A:evaluation_lines()
    local sections = {}
    local measurements, false_tracks, used = 0, 0, 0
    for _, values in ipairs(self.measurements) do measurements = measurements + #values end
    for _, track in ipairs(self.evaluated) do if not next(track.primary_matches) then false_tracks = false_tracks + 1 end; used = used + track.hits end
    sections[#sections + 1] = {
        "summary", "scans " .. self.scans, "measurements " .. measurements, "targets " .. #self.targets, "tracks_created " .. #self.tracks, "tracks_confirmed " .. #self.evaluated,
        "false_tracks " .. false_tracks, "missed_targets " .. (#self.targets - count(self.matched_tracks)), "measurements_used " .. used,
        "conflict_measurements " .. self.conflict_measurements, "conflict_tracks " .. self.conflict_tracks, "greedy_differences " .. self.greedy_differences
    }
    local targets = { "targets" }
    for _, target in ipairs(self.targets) do
        local scans = keys(self.truth[target])
        local length = path_length(map(scans, function(scan) return self.truth[target][scan] end))
        targets[#targets + 1] = string.format("target %d first %d last %d scans %d path %s mean_speed %s", target, scans[1], scans[#scans], #scans, real(length), real(length / (self.times[scans[#scans]] - self.times[scans[1]])))
    end
    sections[#sections + 1] = targets
    local tracks, bound = { "tracks" }, self:parameter("CONSISTENCY_BOUND")
    for _, track in ipairs(self.evaluated) do
        local inside = 0
        for _, value in ipairs(track.nis_values) do if value <= bound then inside = inside + 1 end end
        tracks[#tracks + 1] = string.format("track %d birth %d confirmed %d end %d deleted %s hits %d misses %d longest_gap %d path %s nis %s nis_inside %d/%d", track.number, track.birth, track.confirmed,
            track.last_hit, optional(track.deleted), track.hits, #track.span - track.hits, track.longest_gap, real(track.path), real(Matrix.total(track.nis_values) / #track.nis_values), inside, #track.nis_values)
    end
    sections[#sections + 1] = tracks
    local matching = { "matching" }
    for _, track in ipairs(self.evaluated) do
        local line = "track " .. track.number .. " target " .. optional(track.target)
        if track.target then line = line .. " common " .. #track.common .. " mean_distance " .. real(track.mean_distance) end
        local items = map(keys(track.primary_matches), function(scan) return { scan, track.primary_matches[scan] } end)
        local segments = map(groups(items), function(segment) return segment[1] .. "-" .. segment[2] .. ":" .. segment[3] end)
        matching[#matching + 1] = line .. " matched_scans " .. count(track.primary_matches) .. " " .. listed("segments", segments)
    end
    sections[#sections + 1] = matching
    local rmse_lines, consistency = { "rmse" }, { "consistency" }
    for _, target in ipairs(self.targets) do
        local result = self.target_results[target]
        if not result then rmse_lines[#rmse_lines + 1], consistency[#consistency + 1] = "target " .. target .. " track -", "target " .. target .. " track -"
        else
            rmse_lines[#rmse_lines + 1] = "target " .. target .. " track " .. result.track.number .. " common " .. #result.track.common .. " " .. filter_scores(result.position)
            rmse_lines[#rmse_lines + 1] = "target " .. target .. " velocity " .. result.velocity_count .. " " .. filter_scores(result.velocity)
            local inside = 0
            for _, value in ipairs(result.nees) do if value <= bound then inside = inside + 1 end end
            consistency[#consistency + 1] = string.format("target %d track %d nees %s inside %d/%d", target, result.track.number, real(Matrix.total(result.nees) / #result.nees), inside, #result.nees)
        end
    end
    append(rmse_lines, { "overall position " .. filter_scores(self.overall_position), "overall velocity " .. filter_scores(self.overall_velocity) })
    sections[#sections + 1] = rmse_lines
    local nis_values, edges, observed, expected = {}, self.params.NIS_EDGES, {}, {}
    for _, track in ipairs(self.evaluated) do append(nis_values, track.nis_values) end
    for i = 1, #edges + 1 do observed[i] = 0 end
    for _, value in ipairs(nis_values) do
        local bin = 1
        while bin <= #edges and value >= edges[bin] do bin = bin + 1 end
        observed[bin] = observed[bin] + 1
    end
    local lower = 0.0
    for i = 1, #edges + 1 do
        local upper_probability = i <= #edges and math.exp(-edges[i] / 2) or 0.0
        expected[i] = real(#nis_values * (math.exp(-lower / 2) - upper_probability))
        lower = edges[i]
    end
    consistency[#consistency + 1] = "nis_histogram total " .. #nis_values .. " observed " .. table.concat(observed, " ") .. " expected " .. table.concat(expected, " ")
    sections[#sections + 1] = consistency
    local models = { "models" }
    for _, track in ipairs(self.evaluated) do
        local cv, ca = track.model_logs.cv, track.model_logs.ca
        models[#models + 1] = string.format("track %d updates %d cv %s ca %s better %s", track.number, #track.nis_values, real(cv), real(ca), cv >= ca and "cv" or "ca")
    end
    sections[#sections + 1] = models
    local ospa_lines = { "ospa cutoff " .. real(self:parameter("OSPA_CUTOFF")) .. " order 2", "scan targets tracks cv ca abg imm rts" }
    for scan, sizes in ipairs(self.scan_sizes) do
        local row = { scan, sizes[1], sizes[2] }
        for _, name in ipairs(filters) do row[#row + 1] = real(self.ospa_values[name][scan]) end
        ospa_lines[#ospa_lines + 1] = table.concat(row, " ")
    end
    ospa_lines[#ospa_lines + 1] = "mean " .. table.concat(map(filters, function(name) return real(Matrix.total(self.ospa_values[name]) / self.scans) end), " ")
    sections[#sections + 1] = ospa_lines
    local continuity_lines = { "continuity" }
    for _, name in ipairs(filters) do
        local covered, breaks, swaps = 0, 0, 0
        for _, target in ipairs(self.targets) do local value = self.continuities[name][target]; covered, breaks, swaps = covered + value.covered, breaks + value.breaks, swaps + value.swaps end
        continuity_lines[#continuity_lines + 1] = string.format("%s covered %d breaks %d swaps %d", name, covered, breaks, swaps)
        for _, target in ipairs(self.targets) do
            local value = self.continuities[name][target]
            continuity_lines[#continuity_lines + 1] = string.format("  target %d scans %d covered %d breaks %d swaps %d delay %s", target, count(self.truth[target]), value.covered, value.breaks, value.swaps, optional(value.delay))
        end
    end
    sections[#sections + 1] = continuity_lines
    local imm_lines = { "imm" }
    for _, track in ipairs(self.evaluated) do
        local values = map(track.span, function(scan) return track.high[scan] end)
        local maximum_scan, high = track.birth, {}
        for _, scan in ipairs(track.span) do
            if track.high[scan] > track.high[maximum_scan] then maximum_scan = scan end
            if track.high[scan] > 0.5 then high[#high + 1] = { scan, true } end
        end
        local segments = map(groups(high), function(segment) return segment[1] .. "-" .. segment[2] end)
        imm_lines[#imm_lines + 1] = string.format("track %d mean_high %s max_high %s at %d high_scans %d %s", track.number, real(Matrix.total(values) / #values), real(track.high[maximum_scan]), maximum_scan, #high, listed("segments", segments))
    end
    sections[#sections + 1] = imm_lines
    local lines = {}
    for _, section in ipairs(sections) do if #lines > 0 then lines[#lines + 1] = "" end; append(lines, section) end
    return lines
end
function A:plot_lines()
    local width, height = table.unpack(self.params.PLOT_SIZE)
    local xmin, xmax = table.unpack(self.params.PLOT_X)
    local ymin, ymax = table.unpack(self.params.PLOT_Y)
    local dx, dy = (xmax - xmin) / width, (ymax - ymin) / height
    local function cell(point)
        local column, row = math.floor((point[1] - xmin) / dx) + 1, math.floor((ymax - point[2]) / dy) + 1
        if column >= 1 and column <= width and row >= 1 and row <= height then return row, column end
    end
    local characters, trajectory, counts = {}, {}, {}
    for i, track in ipairs(self.evaluated) do characters[track.number] = string.char(i <= 26 and 64 + i or 96 + i - 26) end
    for row = 1, height do
        trajectory[row], counts[row] = {}, {}
        for column = 1, width do trajectory[row][column], counts[row][column] = " ", 0 end
    end
    for _, target in ipairs(self.targets) do
        for _, scan in ipairs(keys(self.truth[target])) do local row, column = cell(self.truth[target][scan]); if row then trajectory[row][column] = "." end end
    end
    for _, track in ipairs(self.evaluated) do
        for _, scan in ipairs(track.span) do local row, column = cell(track.estimates.rts[scan]); if row then trajectory[row][column] = characters[track.number] end end
    end
    local lines = { string.format("tracks x %s %s y %s %s size %d %d", real(xmin), real(xmax), real(ymin), real(ymax), width, height) }
    append(lines, framed(trajectory))
    for _, track in ipairs(self.evaluated) do lines[#lines + 1] = characters[track.number] .. " track " .. track.number .. " target " .. optional(track.target) end
    for _, measurements in ipairs(self.measurements) do
        for _, measurement in ipairs(measurements) do local row, column = cell(measurement); if row then counts[row][column] = counts[row][column] + 1 end end
    end
    local density = map(counts, function(row) return map(row, function(value) return value == 0 and " " or value < 10 and tostring(value) or "#" end) end)
    append(lines, { "", "measurements" }); append(lines, framed(density)); append(lines, { "", "timeline" })
    for _, target in ipairs(self.targets) do
        local timeline, labels = {}, self.labels[self.primary][target]
        for scan = 1, self.scans do timeline[scan] = not self.truth[target][scan] and " " or labels[scan] and characters[labels[scan]] or "." end
        lines[#lines + 1] = target .. " |" .. table.concat(timeline) .. "|"
    end
    local heights = map(self.ospa_values[self.primary], function(value) return math.floor(10 * value / self:parameter("OSPA_CUTOFF")) end)
    local bars = {}
    for row = 1, 10 do bars[row] = map(heights, function(value) return value >= 11 - row and "#" or " " end) end
    append(lines, { "", "ospa " .. self.primary }); append(lines, framed(bars))
    return lines
end
local analysis = A.read()
analysis:track_all_scans(); analysis:compare_filters(); analysis:evaluate_scans(); analysis:match_tracks(); analysis:evaluate_errors()
local smoothed = { "track,scan,x,y,vx,vy" }
for _, track in ipairs(analysis.evaluated) do
    for _, scan in ipairs(track.span) do local row = { track.number, scan }; append(row, map(track.estimates.rts[scan], real)); smoothed[#smoothed + 1] = table.concat(row, ",") end
end
for filename, lines in pairs({ ["tracks.csv"] = analysis.track_rows, ["smoothed.csv"] = smoothed, ["association_log.txt"] = analysis.association_log,
    ["evaluation.txt"] = analysis:evaluation_lines(), ["track_plot.txt"] = analysis:plot_lines() }) do
    local output = assert(io.open("output/" .. filename, "w"))
    if #lines > 0 then output:write(table.concat(lines, "\n"), "\n") end
    output:close()
end
