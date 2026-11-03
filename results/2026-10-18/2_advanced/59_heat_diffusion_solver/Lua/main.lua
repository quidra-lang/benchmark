local mesh = require('mesh')
local materials = require('materials')
local transient = require('transient')
local steady = require('steady')
local report = require('report')
local function words(line)
    local result = {}
    for token in line:gmatch('%S+') do result[#result + 1] = token end
    return result
end
local function append(target, rows)
    for _, row in ipairs(rows) do target[#target + 1] = row end
end
local function clone(values)
    local result = {}
    for i, value in ipairs(values) do result[i] = value end
    return result
end
local function filled(count, value)
    local result = {}
    for i = 1, count do result[i] = value end
    return result
end
local function verdict(value) return value and 'ok' or 'failed' end
local function read_boundary(plate)
    local segments, sources = {}, {}
    local input = assert(io.open('input/boundary.txt', 'r'))
    for line in input:lines() do
        local t = words(line)
        if t[1] == 'segment' then
            local segment = {name = t[2], edge = t[3], kind = t[6], faces = mesh.segment_faces(plate, t[3], tonumber(t[4]), tonumber(t[5]))}
            if segment.kind == 'fixed' then segment.theta = materials.number(t[7])
            elseif segment.kind == 'convective' then segment.h, segment.theta = materials.number(t[7]), materials.number(t[8]) end
            segments[#segments + 1] = segment
        else
            local cells = mesh.source_cells(plate, tonumber(t[3]), tonumber(t[4]), tonumber(t[5]), tonumber(t[6]))
            local source = {name = t[2], cells = cells, power = materials.number(t[7]), intervals = {}}
            source.weight = source.power / #cells
            for i = 8, #t, 2 do source.intervals[#source.intervals + 1] = {tonumber(t[i]), tonumber(t[i + 1])} end
            sources[#sources + 1] = source
        end
    end
    input:close()
    return segments, sources
end
local function read_parameters(plate)
    local result = {probes = {}, runs = {}}
    local real_keys = {initial = true, tolerance = true, omega = true, alarm = true, limit = true}
    local input = assert(io.open('input/params.txt', 'r'))
    for line in input:lines() do
        local t = words(line)
        local key = t[1]
        if key == 'probe' then result.probes[#result.probes + 1] = {name = t[2], point = mesh.cell(plate, tonumber(t[3]), tonumber(t[4]))}
        elseif key == 'run' then
            local step = tonumber(t[4])
            result.runs[#result.runs + 1] = {name = t[2], method = t[3], step = step, dt = step / 1000}
        elseif key == 'snapshots' or key == 'bands' then
            result[key] = {}
            for i = 2, #t do result[key][#result[key] + 1] = key == 'bands' and materials.number(t[i]) or tonumber(t[i]) end
        elseif key == 'reference' then result.reference = t[2]
        else result[key] = real_keys[key] and materials.number(t[2]) or tonumber(t[2]) end
    end
    input:close()
    return result
end
local function operating(source, now)
    for _, interval in ipairs(source.intervals) do if interval[1] <= now and now < interval[2] then return true end end
    return false
end
local function source_terms(sources, count, now)
    local field, powers = filled(count, 0.0), {}
    for _, source in ipairs(sources) do
        if now == nil or operating(source, now) then
            powers[#powers + 1] = source.power
            for _, point in ipairs(source.cells) do field[point] = field[point] + source.weight end
        end
    end
    return field, transient.sum(powers)
end
local function build_system(plate, material_list, segments, sources)
    local result = {mesh = plate, materials = material_list, segments = segments, sources = sources,
        cell_material = {}, material_cells = {}, capacity = {}, faces = {}, diagonal = {}, beta = {}}
    local indices = {}
    for i, material in ipairs(material_list) do indices[material.code] = i; result.material_cells[i] = {} end
    for p, code in ipairs(plate.codes) do
        local index = indices[code]
        local material = material_list[index]
        result.cell_material[p] = index
        result.material_cells[index][#result.material_cells[index] + 1] = p
        result.capacity[p] = materials.capacity(material, plate.dx, plate.thickness)
        result.faces[p] = {}
        for direction, neighbor in ipairs(plate.neighbors[p]) do
            local conductance = 0.0
            if neighbor > 0 then conductance = materials.interior(material.k, material_list[indices[plate.codes[neighbor]]].k, plate.thickness) end
            result.faces[p][direction] = {neighbor = neighbor, g = conductance}
        end
    end
    for _, segment in ipairs(segments) do
        for _, pair in ipairs(segment.faces) do
            local p, direction = table.unpack(pair)
            local face, material = result.faces[p][direction], material_list[result.cell_material[p]]
            if segment.kind == 'fixed' then face.g = materials.fixed(material.k, plate.thickness)
            elseif segment.kind == 'convective' then face.g = materials.convective(material.k, segment.h, plate.dx, plate.thickness) end
            face.theta = segment.theta
        end
    end
    for p, faces in ipairs(result.faces) do
        local conductances, boundary = {}, {}
        for _, face in ipairs(faces) do
            conductances[#conductances + 1] = face.g
            if face.theta then boundary[#boundary + 1] = face.g * face.theta end
        end
        result.diagonal[p], result.beta[p] = transient.sum(conductances), transient.sum(boundary)
        local maximum_step = result.capacity[p] / result.diagonal[p]
        if result.dt_max == nil or maximum_step < result.dt_max then result.dt_max = maximum_step end
    end
    result.source_all, result.total_power = source_terms(sources, plate.count)
    return result
end
local function hottest(field)
    local point = 1
    for p, value in ipairs(field) do if value > field[point] then point = p end end
    return point
end
local function cell_text(plate, point)
    local row, column = mesh.coordinates(plate, point)
    return row .. ' ' .. column
end
local function summary(prefix, plate, field)
    local point, minimum = hottest(field), field[1]
    for _, value in ipairs(field) do minimum = math.min(minimum, value) end
    return prefix .. ' max ' .. report.real(field[point], 2) .. ' at ' .. cell_text(plate, point) .. ' min ' .. report.real(minimum, 2)
        .. ' mean ' .. report.real(transient.sum(field) / plate.count, 2)
end
local function stored_heat(system, field, initial, cells)
    local terms = {}
    if cells then
        for _, p in ipairs(cells) do terms[#terms + 1] = system.capacity[p] * (field[p] - initial) end
    else
        for p, value in ipairs(field) do terms[p] = system.capacity[p] * (value - initial) end
    end
    return transient.sum(terms)
end
local function segment_flow(system, segment, field)
    if segment.kind == 'insulated' then return 0.0 end
    local terms = {}
    for _, pair in ipairs(segment.faces) do
        local face = system.faces[pair[1]][pair[2]]
        terms[#terms + 1] = face.g * (face.theta - field[pair[1]])
    end
    return transient.sum(terms)
end
local function status(run, system, params)
    local times = {params.end_time, params.probe_every}
    append(times, params.snapshots)
    for _, source in ipairs(system.sources) do for _, interval in ipairs(source.intervals) do append(times, interval) end end
    for _, now in ipairs(times) do if now % run.step ~= 0 then return 'step' end end
    if run.method == 'ftcs' and run.dt > system.dt_max then return 'unstable' end
    return 'accepted'
end
local function step_energy(system, segment, run, previous, updated, intermediate)
    if segment.kind == 'insulated' then return 0.0 end
    local terms = {}
    for _, pair in ipairs(segment.faces) do
        local p, direction = table.unpack(pair)
        local face, temperature = system.faces[p][direction], previous[p]
        if run.method ~= 'ftcs' then
            if segment.edge == 'left' or segment.edge == 'right' then temperature = intermediate[p]
            elseif run.method == 'backward_euler' then temperature = updated[p]
            else temperature = (previous[p] + updated[p]) / 2 end
        end
        terms[#terms + 1] = face.g * (face.theta - temperature)
    end
    return run.dt * transient.sum(terms)
end
local function observe(result, system, params, now, field)
    local point = hottest(field)
    local temperature = field[point]
    if not result.peak or temperature > result.peak.temperature then result.peak = {temperature = temperature, time = now, point = point} end
    if temperature >= params.alarm then
        if not result.alarm then result.alarm = {time = now, point = point} end
        if now > 0 then result.above = result.above + result.run.step end
    end
    if now % params.probe_every == 0 then
        local readings = {}
        for i, probe in ipairs(params.probes) do readings[i] = field[probe.point] end
        result.probe_samples[#result.probe_samples + 1] = {time = now, values = readings}
    end
    for _, snapshot_time in ipairs(params.snapshots) do
        if now == snapshot_time then
            result.snapshots[now] = {field = clone(field), stored = stored_heat(system, field, params.initial), boundary = transient.sum(result.segment_energy), source = result.generated}
        end
    end
end
local function simulate(run, system, params)
    local result = {run = run, status = status(run, system, params)}
    if result.status ~= 'accepted' then return result end
    result.steps = params.end_time // run.step
    result.segment_energy, result.generated = filled(#system.segments, 0.0), 0.0
    result.snapshots, result.probe_samples, result.above = {}, {}, 0
    local field = filled(system.mesh.count, params.initial)
    observe(result, system, params, 0, field)
    for step = 0, result.steps - 1 do
        local sources, power = source_terms(system.sources, system.mesh.count, step * run.step)
        local updated, intermediate = transient.advance(run.method, system, field, sources, run.dt)
        for i, segment in ipairs(system.segments) do result.segment_energy[i] = result.segment_energy[i] + step_energy(system, segment, run, field, updated, intermediate) end
        result.generated = result.generated + run.dt * power
        field = updated
        observe(result, system, params, (step + 1) * run.step, field)
    end
    result.final = field
    result.stored, result.boundary = stored_heat(system, field, params.initial), transient.sum(result.segment_energy)
    result.balanced = math.abs(result.stored - result.boundary - result.generated) <= 0.000001 * (math.abs(result.stored) + math.abs(result.boundary) + math.abs(result.generated))
    return result
end
local function solve_steady(system, params)
    local rhs = {}
    for p = 1, system.mesh.count do rhs[p] = system.beta[p] + system.source_all[p] end
    local vectors = {rhs, system.beta}
    for _, source in ipairs(system.sources) do
        local vector = filled(system.mesh.count, 0.0)
        for _, p in ipairs(source.cells) do vector[p] = 1 / #source.cells end
        vectors[#vectors + 1] = vector
    end
    local fields = steady.band_solve(system, vectors)
    local solution, base, responses = fields[1], fields[2], {}
    for i = 3, #fields do responses[#responses + 1] = fields[i] end
    local results = {steady.iterate(system, params.initial, params.tolerance, params.max_iterations, 'jacobi', 1.0)}
    local changes = results[1].changes
    local rho = math.sqrt(changes[#changes] / changes[#changes - 2])
    local omega_opt = 2 / (1 + math.sqrt(1 - rho * rho))
    for _, method in ipairs({'gauss_seidel', 'sor', 'sor_estimated'}) do
        results[#results + 1] = steady.iterate(system, params.initial, params.tolerance, params.max_iterations, method, method == 'sor_estimated' and omega_opt or params.omega)
    end
    for _, result in ipairs(results) do
        local count = #result.changes
        result.rate = math.sqrt(result.changes[count] / result.changes[count - 2])
        result.milestones = {}
        for _, factor in ipairs({1000, 100, 10, 1}) do
            local milestone = 'never'
            for iteration, change in ipairs(result.changes) do if change < params.tolerance * factor then milestone = tostring(iteration); break end end
            result.milestones[#result.milestones + 1] = milestone
        end
        result.error = 0.0
        for p, value in ipairs(result.field) do result.error = math.max(result.error, math.abs(value - solution[p])) end
        result.residual = steady.residual(system, result.field, rhs)
    end
    return rhs, solution, base, responses, results, rho, omega_opt
end
local function duty(source, end_time)
    local duration = 0
    for _, interval in ipairs(source.intervals) do duration = duration + math.min(interval[2], end_time) - math.min(interval[1], end_time) end
    return duration / end_time
end
local function selected_values(field, cells)
    local result = {}
    for _, p in ipairs(cells) do result[#result + 1] = field[p] end
    return result
end
local function extrema(values)
    local low, high = values[1], values[1]
    for _, value in ipairs(values) do low, high = math.min(low, value), math.max(high, value) end
    return low, high
end
local function steady_lines(system, params, solution, base, responses, iterative)
    local plate = system.mesh
    local lines = {summary('steady', plate, solution)}
    append(lines, report.temperatures(plate, solution))
    for i, material in ipairs(system.materials) do
        local values = selected_values(solution, system.material_cells[i])
        local low, high = extrema(values)
        lines[#lines + 1] = 'material ' .. material.code .. ' ' .. material.name .. ' cells ' .. #values .. ' min ' .. report.real(low, 2)
            .. ' max ' .. report.real(high, 2) .. ' mean ' .. report.real(transient.sum(values) / #values, 2)
    end
    local duties = {}
    for i, source in ipairs(system.sources) do
        duties[i] = duty(source, params.end_time)
        local values = selected_values(solution, source.cells)
        local _, high = extrema(values)
        lines[#lines + 1] = 'source ' .. source.name .. ' power ' .. report.real(source.power, 4) .. ' duty ' .. report.real(duties[i], 4)
            .. ' mean ' .. report.real(transient.sum(values) / #values, 2) .. ' max ' .. report.real(high, 2)
    end
    for _, source in ipairs(system.sources) do
        for i, contributor in ipairs(system.sources) do
            local coefficient = transient.sum(selected_values(responses[i], source.cells)) / #source.cells
            lines[#lines + 1] = 'influence ' .. source.name .. ' ' .. contributor.name .. ' ' .. report.real(coefficient, 4)
        end
    end
    local maximum_error, duty_field = 0.0, {}
    for p = 1, plate.count do
        local value, average = base[p], base[p]
        for i, source in ipairs(system.sources) do
            value = value + source.power * responses[i][p]
            average = average + (duties[i] * source.power) * responses[i][p]
        end
        maximum_error = math.max(maximum_error, math.abs(value - solution[p]))
        duty_field[p] = average
    end
    lines[#lines + 1] = 'superposition ' .. verdict(maximum_error <= 0.000001)
    for i, source in ipairs(system.sources) do
        for _, segment in ipairs(system.segments) do
            local terms = {}
            if segment.kind ~= 'insulated' then
                for _, pair in ipairs(segment.faces) do terms[#terms + 1] = system.faces[pair[1]][pair[2]].g * responses[i][pair[1]] end
            end
            lines[#lines + 1] = 'path ' .. source.name .. ' ' .. segment.name .. ' ' .. report.real(transient.sum(terms), 4)
        end
    end
    lines[#lines + 1] = summary('duty_steady', plate, duty_field)
    for i, source in ipairs(system.sources) do
        local minimum, selected
        for p = 1, plate.count do
            local power = (params.limit - (solution[p] - source.power * responses[i][p])) / responses[i][p]
            if minimum == nil or power < minimum then minimum, selected = power, p end
        end
        lines[#lines + 1] = 'headroom ' .. source.name .. ' max_power ' .. report.real(minimum, 4) .. ' at ' .. cell_text(plate, selected)
    end
    local pairs = {}
    local gradient, first_point, second_point = -1.0, 1, 1
    for p, faces in ipairs(system.faces) do
        for _, direction in ipairs({2, 4}) do
            local face, q = faces[direction], faces[direction].neighbor
            if q > 0 then
                local current_gradient = math.abs(solution[p] - solution[q]) / plate.dx
                if current_gradient > gradient then gradient, first_point, second_point = current_gradient, p, q end
                local a, b = system.cell_material[p], system.cell_material[q]
                if a ~= b then
                    local flow = face.g * (solution[p] - solution[q])
                    if a > b then a, b, flow = b, a, -flow end
                    pairs[a] = pairs[a] or {}
                    local group = pairs[a][b] or {count = 0, forward = 0.0, backward = 0.0}
                    pairs[a][b] = group
                    group.count = group.count + 1
                    if flow > 0 then group.forward = group.forward + flow elseif flow < 0 then group.backward = group.backward + math.abs(flow) end
                end
            end
        end
    end
    for a, material in ipairs(system.materials) do
        for b = a + 1, #system.materials do
            local group = pairs[a] and pairs[a][b]
            if group then lines[#lines + 1] = 'interface ' .. material.code .. ' ' .. system.materials[b].code .. ' faces ' .. group.count
                .. ' forward ' .. report.real(group.forward, 4) .. ' backward ' .. report.real(group.backward, 4) end
        end
    end
    local flows, absolute_flows = {}, {}
    for i, segment in ipairs(system.segments) do
        flows[i] = segment_flow(system, segment, solution)
        absolute_flows[i] = math.abs(flows[i])
        lines[#lines + 1] = 'segment ' .. segment.name .. ' ' .. segment.edge .. ' ' .. segment.kind .. ' flow ' .. report.real(flows[i], 4)
    end
    lines[#lines + 1] = 'sources ' .. report.real(system.total_power, 4)
    lines[#lines + 1] = 'balance ' .. verdict(math.abs(transient.sum(flows) + system.total_power) <= 0.000001 * (transient.sum(absolute_flows) + system.total_power))
    lines[#lines + 1] = 'max_gradient ' .. report.real(gradient, 2) .. ' between ' .. cell_text(plate, first_point) .. ' and ' .. cell_text(plate, second_point)
    for _, result in ipairs(iterative) do
        local prefix = 'solver ' .. result.method
        if result.method == 'sor' or result.method == 'sor_estimated' then prefix = prefix .. ' omega ' .. report.real(result.omega, 4) end
        lines[#lines + 1] = prefix .. ' iterations ' .. result.iterations .. ' converged ' .. (result.converged and 'yes' or 'no')
            .. ' rate ' .. report.real(result.rate, 6) .. ' milestones ' .. table.concat(result.milestones, ' ')
    end
    return lines
end
local function rejected(result, max_dt)
    local run = result.run
    local line = 'run ' .. run.name .. ' ' .. run.method .. ' dt ' .. report.time(run.step) .. ' rejected ' .. result.status
    if result.status == 'unstable' and max_dt then line = line .. ' max_dt ' .. report.real(max_dt, 4) end
    return line
end
local function snapshot_lines(system, params, results)
    local lines = {}
    for _, result in ipairs(results) do
        local run = result.run
        if result.status ~= 'accepted' then lines[#lines + 1] = rejected(result, system.dt_max)
        else
            for _, now in ipairs(params.snapshots) do
                local field = result.snapshots[now].field
                local prefix = 'run ' .. run.name .. ' ' .. run.method .. ' dt ' .. report.time(run.step) .. ' time ' .. report.time(now)
                lines[#lines + 1] = summary(prefix, system.mesh, field)
                append(lines, report.temperatures(system.mesh, field))
            end
        end
    end
    return lines
end
local function probe_lines(params, results)
    local lines = {'run,time,probe,temperature'}
    for _, result in ipairs(results) do
        if result.status == 'accepted' then
            for _, sample in ipairs(result.probe_samples) do
                for i, probe in ipairs(params.probes) do
                    lines[#lines + 1] = result.run.name .. ',' .. report.time(sample.time) .. ',' .. probe.name .. ',' .. report.real(sample.values[i], 3)
                end
            end
        end
    end
    return lines
end
local function comparison_lines(system, params, results, reference, solution, rhs, iterative, rho, omega_opt)
    local lines = {'ftcs_max_dt ' .. report.real(system.dt_max, 4)}
    for _, result in ipairs(results) do
        local run = result.run
        if result.status ~= 'accepted' then lines[#lines + 1] = rejected(result)
        else
            local peak, alarm = result.peak, 'never'
            if result.alarm then alarm = report.time(result.alarm.time) .. ' at ' .. cell_text(system.mesh, result.alarm.point) end
            lines[#lines + 1] = 'run ' .. run.name .. ' ' .. run.method .. ' dt ' .. report.time(run.step) .. ' steps ' .. result.steps .. ' peak '
                .. report.real(peak.temperature, 2) .. ' time ' .. report.time(peak.time) .. ' at ' .. cell_text(system.mesh, peak.point) .. ' alarm ' .. alarm .. ' above ' .. report.time(result.above)
            lines[#lines + 1] = 'energy ' .. run.name .. ' stored ' .. report.real(result.stored, 2) .. ' boundary ' .. report.real(result.boundary, 2)
                .. ' source ' .. report.real(result.generated, 2) .. ' balance ' .. verdict(result.balanced)
            for _, now in ipairs(params.snapshots) do
                local snapshot = result.snapshots[now]
                lines[#lines + 1] = 'energy_at ' .. run.name .. ' time ' .. report.time(now) .. ' stored ' .. report.real(snapshot.stored, 2)
                    .. ' boundary ' .. report.real(snapshot.boundary, 2) .. ' source ' .. report.real(snapshot.source, 2)
            end
            for i, material in ipairs(system.materials) do
                local value = stored_heat(system, result.final, params.initial, system.material_cells[i])
                lines[#lines + 1] = 'energy_material ' .. run.name .. ' ' .. material.code .. ' ' .. report.real(value, 2)
            end
            for i, segment in ipairs(system.segments) do lines[#lines + 1] = 'energy_segment ' .. run.name .. ' ' .. segment.name .. ' ' .. report.real(result.segment_energy[i], 2) end
            for i, probe in ipairs(params.probes) do
                local first = result.probe_samples[1]
                local low, high, low_time, high_time = first.values[i], first.values[i], first.time, first.time
                for j = 2, #result.probe_samples do
                    local sample = result.probe_samples[j]
                    if sample.values[i] > high then high, high_time = sample.values[i], sample.time end
                    if sample.values[i] < low then low, low_time = sample.values[i], sample.time end
                end
                lines[#lines + 1] = 'probe_summary ' .. run.name .. ' ' .. probe.name .. ' max ' .. report.real(high, 3) .. ' time ' .. report.time(high_time)
                    .. ' min ' .. report.real(low, 3) .. ' time ' .. report.time(low_time)
            end
            if result ~= reference then
                for _, now in ipairs(params.snapshots) do
                    local errors, maximum = {}, 0.0
                    for p, value in ipairs(result.snapshots[now].field) do
                        local error = math.abs(value - reference.snapshots[now].field[p])
                        errors[p], maximum = error * error, math.max(maximum, error)
                    end
                    local rms = math.sqrt(transient.sum(errors) / system.mesh.count)
                    lines[#lines + 1] = 'compare ' .. run.name .. ' ' .. reference.run.name .. ' time ' .. report.time(now) .. ' max_diff ' .. report.real(maximum, 6) .. ' rms_diff ' .. report.real(rms, 6)
                end
            end
            local difference = 0.0
            for p, value in ipairs(result.final) do difference = math.max(difference, math.abs(value - solution[p])) end
            lines[#lines + 1] = 'final ' .. run.name .. ' steady_max_diff ' .. report.real(difference, 6)
        end
    end
    lines[#lines + 1] = 'steady direct max_residual ' .. report.real(steady.residual(system, solution, rhs), 6)
    for _, result in ipairs(iterative) do lines[#lines + 1] = 'steady ' .. result.method .. ' iterations ' .. result.iterations .. ' max_diff ' .. report.real(result.error, 6) .. ' max_residual ' .. report.real(result.residual, 6) end
    lines[#lines + 1] = 'jacobi_spectral_radius ' .. report.real(rho, 6) .. ' squared ' .. report.real(rho * rho, 6)
    lines[#lines + 1] = 'omega_estimated ' .. report.real(omega_opt, 4)
    return lines
end
local function isotherm_lines(system, params, solution, reference)
    local lines = {}
    local function add(prefix, field)
        local counts, rows = report.isotherms(system.mesh, field, params.bands)
        local values = {}
        for i, count in ipairs(counts) do values[i] = tostring(count) end
        lines[#lines + 1] = prefix .. ' counts ' .. table.concat(values, ' ')
        append(lines, rows)
    end
    add('isotherms steady', solution)
    for _, now in ipairs(params.snapshots) do add('isotherms ' .. reference.run.name .. ' time ' .. report.time(now), reference.snapshots[now].field) end
    return lines
end
local plate, material_list = mesh.read(), materials.read()
local segments, sources = read_boundary(plate)
local params = read_parameters(plate)
local system = build_system(plate, material_list, segments, sources)
local rhs, solution, base, responses, iterative, rho, omega_opt = solve_steady(system, params)
local results, reference = {}, nil
for _, run in ipairs(params.runs) do
    local result = simulate(run, system, params)
    results[#results + 1] = result
    if run.name == params.reference then reference = result end
end
report.write('snapshots.txt', snapshot_lines(system, params, results))
report.write('probes.csv', probe_lines(params, results))
report.write('steady_state.txt', steady_lines(system, params, solution, base, responses, iterative))
report.write('solver_comparison.txt', comparison_lines(system, params, results, reference, solution, rhs, iterative, rho, omega_opt))
report.write('isotherms.txt', isotherm_lines(system, params, solution, reference))
