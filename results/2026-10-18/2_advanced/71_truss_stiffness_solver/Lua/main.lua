package.path = 'Lua/?.lua;' .. package.path
local model_io = require('model_io')
local assembly = require('assembly')
local solver = require('solver')
local postprocess = require('postprocess')
local design = require('design')
local model = model_io.read_model()
local nodes, members, settings = model.nodes, model.members, model.settings
local function real(value, digits)
    local text = string.format('%.' .. (digits or 4) .. 'f', value)
    return text:sub(1, 1) == '-' and tonumber(text) == 0 and text:sub(2) or text
end
local function rounded(value) return tonumber(real(value)) end
local function line(lines, ...) lines[#lines + 1] = table.concat({...}, ' ') end
local function append(destination, source) for _, value in ipairs(source) do destination[#destination + 1] = value end end
local function extreme(values, minimum)
    local chosen = 1
    for i = 2, #values do
        local a, b = rounded(values[i]), rounded(values[chosen])
        if minimum and a < b or not minimum and a > b then chosen = i end
    end
    return chosen
end
local function set_keys(set)
    local result = {}
    for key in pairs(set) do result[#result + 1] = key end
    return result
end
local neighbors, degrees_of_nodes = {}, {}
for v = 1, #nodes do neighbors[v] = {} end
for _, member in ipairs(members) do neighbors[member.start][member.finish], neighbors[member.finish][member.start] = true, true end
for v = 1, #nodes do degrees_of_nodes[v] = #set_keys(neighbors[v]) end
local function node_less(a, b)
    return degrees_of_nodes[a] < degrees_of_nodes[b] or degrees_of_nodes[a] == degrees_of_nodes[b] and nodes[a].identifier < nodes[b].identifier
end
local start = 1
for v = 2, #nodes do if node_less(v, start) then start = v end end
local queue, visited, head = {start}, {[start] = true}, 1
while head <= #queue do
    local node = queue[head]
    head = head + 1
    local following = {}
    for neighbor in pairs(neighbors[node]) do if not visited[neighbor] then following[#following + 1] = neighbor end end
    table.sort(following, node_less)
    for _, neighbor in ipairs(following) do queue[#queue + 1] = neighbor; visited[neighbor] = true end
end
local order, numbers, node_dofs, owners = {}, {}, {}, {}
for i = #queue, 1, -1 do order[#order + 1] = queue[i]; numbers[queue[i]] = #order - 1 end
local nd = 2 * #nodes
for node = 1, #nodes do
    node_dofs[node] = {2 * numbers[node] + 1, 2 * numbers[node] + 2}
    for axis = 1, 2 do owners[node_dofs[node][axis]] = {node, axis} end
end
local prescribed, support_directions, restrained, free, restrained_set = assembly.zeros(nd), {}, {}, {}, {}
for _, support in ipairs(model.supports) do
    for axis = 1, 2 do
        if support.fixed[axis] then
            local degree = node_dofs[support.node][axis]
            prescribed[degree] = support.prescribed[axis]
            support_directions[#support_directions + 1] = {support.node, axis, degree}
            restrained[#restrained + 1], restrained_set[degree] = degree, true
        end
    end
end
table.sort(restrained)
for degree = 1, nd do if not restrained_set[degree] then free[#free + 1] = degree end end
local geometry = assembly.member_geometry(nodes, members, node_dofs)
local groups, group_order, combination_definitions, result_order = {}, {}, {}, {}
for number, member in ipairs(members) do
    if not groups[member.group] then groups[member.group] = {}; group_order[#group_order + 1] = member.group end
    groups[member.group][#groups[member.group] + 1] = number
end
for _, case in ipairs(model.cases) do result_order[#result_order + 1] = {'case', case.name} end
for _, combination in ipairs(model.combinations) do combination_definitions[combination.name] = combination; result_order[#result_order + 1] = {'combination', combination.name} end
local deck, deck_x = settings.deck, {}
for i, node in ipairs(deck) do deck_x[i] = nodes[node].x end
local choices, final_system, properties, results, combinations, limits, utilizations, governing, governing_cases, weight
local units = {}
local function make_system(section_choices, removed)
    local props = assembly.member_properties(model, section_choices, geometry)
    local matrix = assembly.assemble(geometry, props, nd, removed)
    local free_matrix = {}
    for i, row in ipairs(free) do free_matrix[i] = {}; for j, column in ipairs(free) do free_matrix[i][j] = matrix[row][column] end end
    local lower, unstable = solver.cholesky(free_matrix, free)
    return {properties = props, matrix = matrix, free_matrix = free_matrix, lower = lower, unstable = unstable, removed = removed}
end
local function displacement(system, force, settlement)
    local result, right = assembly.zeros(nd), {}
    for _, degree in ipairs(restrained) do result[degree] = settlement and prescribed[degree] or 0.0 end
    for _, degree in ipairs(free) do
        local value = force[degree]
        for _, fixed in ipairs(restrained) do value = value - system.matrix[degree][fixed] * result[fixed] end
        right[#right + 1] = value
    end
    local solution = solver.solve(system.lower, right)
    for i, degree in ipairs(free) do result[degree] = solution[i] end
    return result
end
local function case_result(system, case)
    local loading = assembly.load_vectors(case, geometry, system.properties, node_dofs, nd, system.removed)
    local d = displacement(system, loading.total, loading.settlement)
    return {name = case.name, displacement = d, forces = postprocess.axial_forces(geometry, system.properties, d, loading.temperature, system.removed),
        reactions = postprocess.reactions(system.matrix, d, loading.total, restrained), external = loading.external}
end
local function analyze(system, only_combination)
    local needed, active, analyzed = {}, only_combination and {only_combination} or model.combinations, {}
    for _, combination in ipairs(active) do for _, term in ipairs(combination.terms) do needed[term[1]] = true end end
    for _, case in ipairs(model.cases) do if not only_combination or needed[case.name] then analyzed[case.name] = case_result(system, case) end end
    for _, combination in ipairs(active) do analyzed[combination.name] = postprocess.superpose(combination, analyzed) end
    return analyzed
end
local function unit_result(node)
    if not units[node] then
        local force = assembly.zeros(nd)
        force[node_dofs[node][2]] = -1000.0
        local d = displacement(final_system, force)
        units[node] = {displacement = d, forces = postprocess.axial_forces(geometry, properties, d, assembly.zeros(#members)), reactions = postprocess.reactions(final_system.matrix, d, force, restrained), external = force}
    end
    return units[node]
end
local function design_sections()
    choices = {}
    for i, member in ipairs(members) do choices[i] = member.section end
    local history, converged, last_round = {}, false, 0
    for round = 1, 10 do
        last_round = round
        final_system = make_system(choices)
        properties, results = final_system.properties, analyze(final_system)
        combinations, limits, utilizations = {}, {}, {}
        for _, definition in ipairs(model.combinations) do combinations[#combinations + 1] = results[definition.name] end
        local maximum, maximum_member, maximum_case
        weight = 0.0
        for i, prop in ipairs(properties) do
            limits[i] = design.slenderness_limit(i, combinations, settings.slenderness)
            utilizations[i] = {}
            weight = weight + assembly.member_weight(prop, geometry[i])
            for c, result in ipairs(combinations) do
                local value = design.utilization(result.forces[i], prop, geometry[i])
                utilizations[i][c] = value
                if not maximum or rounded(value) > rounded(maximum) then maximum, maximum_member, maximum_case = value, i, c end
            end
        end
        local changes = {}
        for _, name in ipairs(group_order) do
            local group = groups[name]
            local chosen = design.select_section(group, model.sections, properties, geometry, combinations, limits)
            local current = choices[group[1]]
            if chosen ~= current then
                local largest
                for _, member in ipairs(group) do for _, value in ipairs(utilizations[member]) do if not largest or rounded(value) > rounded(largest) then largest = value end end end
                changes[#changes + 1] = {name, current, chosen, largest}
            end
        end
        line(history, 'round', round, 'weight', real(weight / 1000), 'max_utilization', real(maximum), 'at', members[maximum_member].identifier, combinations[maximum_case].name, 'changes', #changes)
        for _, change in ipairs(changes) do line(history, 'change', change[1], model.sections[change[2]].name, model.sections[change[3]].name, 'utilization', real(change[4])) end
        converged = #changes == 0
        if converged or round == 10 then break end
        for _, change in ipairs(changes) do for _, member in ipairs(groups[change[1]]) do choices[member] = change[3] end end
    end
    governing, governing_cases = {}, {}
    for i, values in ipairs(utilizations) do governing_cases[i] = extreme(values); governing[i] = values[governing_cases[i]] end
    line(history, 'result', converged and 'converged' or 'not_converged', 'rounds', last_round)
    return history
end
local function magnitudes(result)
    local values = {}
    for i, dofs in ipairs(node_dofs) do local ux, uy = result.displacement[dofs[1]], result.displacement[dofs[2]]; values[i] = math.sqrt(ux * ux + uy * uy) end
    return values
end
local function design_report(history)
    local lines = {}
    append(lines, history)
    for _, name in ipairs(group_order) do
        local group, values = groups[name], {}
        for _, member in ipairs(group) do values[#values + 1] = governing[member] end
        local member = group[extreme(values)]
        line(lines, 'group', name, 'section', model.sections[choices[group[1]]].name, 'members', #group, 'utilization', real(governing[member]), 'at', members[member].identifier)
    end
    for i, member in ipairs(members) do
        local slender = design.slenderness(properties[i], geometry[i])
        line(lines, 'member', member.identifier, 'group', member.group, 'section', model.sections[choices[i]].name, 'utilization', real(governing[i]), 'governing', combinations[governing_cases[i]].name, 'slenderness', real(slender), 'limit', real(limits[i]), governing[i] <= 1 and slender <= limits[i] and 'ok' or 'over')
    end
    local ranking = {}
    for i = 1, #members do ranking[i] = i end
    table.sort(ranking, function(a, b) local x, y = rounded(governing[a]), rounded(governing[b]); return x > y or x == y and a < b end)
    for rank = 1, math.min(5, #ranking) do local member = ranking[rank]; line(lines, 'rank', rank, 'member', members[member].identifier, 'utilization', real(governing[member])) end
    for i, member in ipairs(members) do
        local values = {}
        for _, result in ipairs(combinations) do values[#values + 1] = result.forces[i] / 1000 end
        local largest, smallest = extreme(values), extreme(values, true)
        line(lines, 'envelope', member.identifier, 'max', real(values[largest]), combinations[largest].name, 'min', real(values[smallest]), combinations[smallest].name)
    end
    for section, description in ipairs(model.sections) do
        local count, length = 0, 0.0
        for member, choice in ipairs(choices) do if choice == section then count, length = count + 1, length + geometry[member].length end end
        if count > 0 then line(lines, 'section', description.name, 'members', count, 'length', real(length)) end
    end
    line(lines, 'weight', real(weight / 1000))
    return lines
end
local function result_summary(kind, result)
    local values, energy = magnitudes(result), 0.0
    local node = extreme(values)
    for i, force in ipairs(result.forces) do energy = energy + force * force * geometry[i].length / (2 * properties[i].young * properties[i].area) end
    local reactions_total, loads_total, scale = {0.0, 0.0}, {0.0, 0.0}, 1.0
    for _, dofs in ipairs(node_dofs) do for axis = 1, 2 do reactions_total[axis] = reactions_total[axis] + result.reactions[dofs[axis]]; loads_total[axis] = loads_total[axis] + result.external[dofs[axis]] end end
    for _, value in ipairs(result.external) do scale = math.max(scale, math.abs(value)) end
    for _, value in ipairs(result.reactions) do scale = math.max(scale, math.abs(value)) end
    local equilibrium = postprocess.equilibrium_residual(result, geometry) <= 0.000001 * scale and 'ok' or 'failed'
    return table.concat({kind, result.name, 'equilibrium', equilibrium, 'max_displacement', real(values[node]), 'at', nodes[node].identifier, 'energy', real(energy / 1000), 'reactions', real(reactions_total[1] / 1000), real(reactions_total[2] / 1000), 'loads', real(loads_total[1] / 1000), real(loads_total[2] / 1000)}, ' ')
end
local function deflection_report()
    local name, ratio = table.unpack(settings.deflection)
    local result, fixed, anchors, lines = results[name], {}, {}, {}
    for _, direction in ipairs(support_directions) do if direction[2] == 2 then fixed[direction[1]] = true end end
    for i, node in ipairs(deck) do if fixed[node] then anchors[#anchors + 1] = i end end
    for span = 1, #anchors - 1 do
        local first, last = anchors[span], anchors[span + 1]
        local left, right, xa, xb = deck[first], deck[last], deck_x[first], deck_x[last]
        local va, vb = result.displacement[node_dofs[left][2]], result.displacement[node_dofs[right][2]]
        local deflections, interior = {}, {}
        for i = first + 1, last - 1 do interior[#interior + 1] = deck[i]; deflections[#deflections + 1] = math.abs(result.displacement[node_dofs[deck[i]][2]] - (va + (vb - va) * (deck_x[i] - xa) / (xb - xa))) end
        local chosen = extreme(deflections)
        local maximum, node, limit = deflections[chosen], interior[chosen], (xb - xa) / ratio
        line(lines, 'deflection', name, 'span', nodes[left].identifier, nodes[right].identifier, 'max', real(maximum), 'at', nodes[node].identifier, 'limit', real(limit), maximum <= limit and 'ok' or 'exceeded')
        local unit, virtual = unit_result(node), 0.0
        for i, force in ipairs(result.forces) do virtual = virtual + force * (unit.forces[i] / 1000) * geometry[i].length / (properties[i].young * properties[i].area) end
        local stiffness = -result.displacement[node_dofs[node][2]]
        line(lines, 'virtual_work', name, 'node', nodes[node].identifier, 'stiffness', real(stiffness), 'virtual', real(virtual), math.abs(virtual - stiffness) <= 0.000001 * math.max(1, math.abs(stiffness)) and 'ok' or 'failed')
    end
    return lines
end
local function removal_report()
    local definition, lines = combination_definitions[settings.removal], {}
    for removed, description in ipairs(members) do
        local system = make_system(choices, removed)
        if system.unstable then
            local owner = owners[system.unstable]
            line(lines, 'removal', description.identifier, 'unstable at', nodes[owner[1]].identifier, owner[2] == 1 and 'x' or 'y')
        else
            local result = analyze(system, definition)[definition.name]
            local remaining, values = {}, {}
            for i = 1, #members do if i ~= removed then remaining[#remaining + 1] = i; values[#values + 1] = design.utilization(result.forces[i], system.properties[i], geometry[i]) end end
            local largest, displacement_values = extreme(values), magnitudes(result)
            local node = extreme(displacement_values)
            line(lines, 'removal', description.identifier, 'stable max_utilization', real(values[largest]), 'at', members[remaining[largest]].identifier, 'max_displacement', real(displacement_values[node]), 'at', nodes[node].identifier)
        end
    end
    return lines
end
local function numbering_metrics(numbering)
    local bandwidth, profile = 0, 0
    for _, member in ipairs(members) do bandwidth = math.max(bandwidth, math.abs(numbering[member.start] - numbering[member.finish])) end
    for node = 1, #nodes do local minimum = numbering[node]; for adjacent in pairs(neighbors[node]) do minimum = math.min(minimum, numbering[adjacent]) end; profile = profile + numbering[node] - minimum end
    return bandwidth, profile
end
local function analysis_report()
    local original, order_ids = {}, {}
    for i = 1, #nodes do original[i] = i - 1 end
    for _, node in ipairs(order) do order_ids[#order_ids + 1] = nodes[node].identifier end
    local before_bandwidth, before_profile = numbering_metrics(original)
    local after_bandwidth, after_profile = numbering_metrics(numbers)
    local lines = {}
    line(lines, 'model nodes', #nodes, 'members', #members, 'supports', #model.supports, 'free_dofs', #free, 'restrained_dofs', #restrained, 'indeterminacy', #members + #restrained - 2 * #nodes)
    line(lines, 'renumbering', table.concat(order_ids, ' ')); line(lines, 'bandwidth before', before_bandwidth, 'after', after_bandwidth); line(lines, 'profile before', before_profile, 'after', after_profile)
    for i, member in ipairs(members) do local shape = geometry[i]; line(lines, 'member', member.identifier, 'nodes', nodes[member.start].identifier, nodes[member.finish].identifier, 'length', real(shape.length), 'cos', real(shape.cosine, 6), 'sin', real(shape.sine, 6)) end
    for _, result in ipairs(result_order) do lines[#lines + 1] = result_summary(result[1], results[result[2]]) end
    for _, direction in ipairs(support_directions) do
        local node, axis, degree = table.unpack(direction)
        local values, uplift = {}, false
        for _, result in ipairs(combinations) do values[#values + 1] = result.reactions[degree] / 1000; if result.reactions[degree] < 0 then uplift = true end end
        local largest, smallest = extreme(values), extreme(values, true)
        local text = table.concat({'reaction_envelope', nodes[node].identifier, axis == 1 and 'x' or 'y', 'max', real(values[largest]), combinations[largest].name, 'min', real(values[smallest]), combinations[smallest].name}, ' ')
        if axis == 2 then text = text .. ' uplift ' .. (uplift and 'yes' or 'no') end
        lines[#lines + 1] = text
    end
    local displacement_values = {}
    for c, result in ipairs(combinations) do displacement_values[c] = magnitudes(result) end
    for node, description in ipairs(nodes) do
        local values = {}
        for c = 1, #combinations do values[c] = displacement_values[c][node] end
        local largest = extreme(values)
        line(lines, 'displacement_envelope', description.identifier, 'max', real(values[largest]), combinations[largest].name)
    end
    append(lines, deflection_report()); append(lines, removal_report())
    return lines
end

local function ordinate(ordinates, position)
    if position < deck_x[1] or position > deck_x[#deck_x] then return 0.0 end
    if position == deck_x[#deck_x] then return ordinates[#ordinates] end
    local index = 1
    while deck_x[index + 1] <= position do index = index + 1 end
    return ordinates[index] + (ordinates[index + 1] - ordinates[index]) * (position - deck_x[index]) / (deck_x[index + 1] - deck_x[index])
end
local function vehicle_range(ordinates, positions, axles)
    local effects = {}
    for _, position in ipairs(positions) do
        local effect = 0.0
        for _, axle in ipairs(axles) do effect = effect + axle[2] * ordinate(ordinates, position - axle[1]) end
        effects[#effects + 1] = effect
    end
    local largest, smallest = extreme(effects), extreme(effects, true)
    return effects[largest], positions[largest], effects[smallest], positions[smallest]
end
local function influence_report()
    local member_ordinates, reaction_ordinates, lines = {}, {}, {}
    for i = 1, #members do member_ordinates[i] = {} end
    for _, direction in ipairs(support_directions) do reaction_ordinates[direction[3]] = {} end
    for _, node in ipairs(deck) do
        local result = unit_result(node)
        for i, force in ipairs(result.forces) do member_ordinates[i][#member_ordinates[i] + 1] = force / 1000 end
        for _, direction in ipairs(support_directions) do local degree = direction[3]; reaction_ordinates[degree][#reaction_ordinates[degree] + 1] = result.reactions[degree] / 1000 end
    end
    for _, member in ipairs(settings.influence) do
        local ordinates, positive, negative = member_ordinates[member], 0.0, 0.0
        line(lines, 'influence', members[member].identifier)
        for i, node in ipairs(deck) do line(lines, 'node', nodes[node].identifier, real(ordinates[i])); if ordinates[i] > 0 then positive = positive + ordinates[i] elseif ordinates[i] < 0 then negative = negative + ordinates[i] end end
        local largest, smallest = extreme(ordinates), extreme(ordinates, true)
        line(lines, 'max', real(ordinates[largest]), 'at', nodes[deck[largest]].identifier, 'min', real(ordinates[smallest]), 'at', nodes[deck[smallest]].identifier, 'positive', real(positive), 'negative', real(negative))
        local crossings = {}
        for i = 1, #ordinates - 1 do
            local a, b = ordinates[i], ordinates[i + 1]
            if a > 0 and b < 0 or a < 0 and b > 0 then crossings[#crossings + 1] = real(deck_x[i] + (deck_x[i + 1] - deck_x[i]) * a / (a - b), 1) end
        end
        lines[#lines + 1] = 'crossings ' .. #crossings .. (#crossings > 0 and ' ' .. table.concat(crossings, ' ') or '')
    end
    local step, axles = table.unpack(settings.vehicle)
    local positions, member_ranges = {}, {}
    for position = deck_x[1], deck_x[#deck_x] + axles[#axles][1], step do positions[#positions + 1] = position end
    line(lines, 'vehicle axles', #axles, 'positions', #positions)
    for i, member in ipairs(members) do
        local largest, high, smallest, low = vehicle_range(member_ordinates[i], positions, axles)
        member_ranges[i] = {largest, smallest}
        line(lines, 'vehicle_member', member.identifier, 'max', real(largest), 'at', high, 'min', real(smallest), 'at', low)
    end
    for _, direction in ipairs(support_directions) do
        local largest, high, smallest, low = vehicle_range(reaction_ordinates[direction[3]], positions, axles)
        line(lines, 'vehicle_reaction', nodes[direction[1]].identifier, direction[2] == 1 and 'x' or 'y', 'max', real(largest), 'at', high, 'min', real(smallest), 'at', low)
    end
    local name, dead_factor, vehicle_factor = table.unpack(settings.rating)
    local ratings, rating_values = {}, {}
    for i, member in ipairs(members) do
        local prop, shape = properties[i], geometry[i]
        local largest, smallest = table.unpack(member_ranges[i])
        local dead_force = results[name].forces[i] / 1000
        local tension_capacity = prop.area * prop.yield_stress / 1000
        local compression_capacity = math.min(prop.area * prop.yield_stress, design.buckling(prop, shape)) / 1000
        local tension, compression = 'none', 'none'
        if rounded(largest) > 0 then
            local rating = (tension_capacity - dead_factor * dead_force) / (vehicle_factor * largest)
            tension = real(rating); ratings[#ratings + 1] = {i, 'tension'}; rating_values[#rating_values + 1] = rating
        end
        if rounded(smallest) < 0 then
            local rating = (compression_capacity + dead_factor * dead_force) / (vehicle_factor * (-smallest))
            compression = real(rating); ratings[#ratings + 1] = {i, 'compression'}; rating_values[#rating_values + 1] = rating
        end
        line(lines, 'rating', member.identifier, 'tension', tension, 'compression', compression)
    end
    local chosen = extreme(rating_values, true)
    line(lines, 'rating_min', real(rating_values[chosen]), 'at', members[ratings[chosen][1]].identifier, ratings[chosen][2])
    return lines
end
local function vibration_report()
    local name, mode_count, iterations = table.unpack(settings.vibration)
    local external, masses, free_masses, total_mass = results[name].external, {}, {}, 0.0
    for i, dofs in ipairs(node_dofs) do masses[i] = -external[dofs[2]] / 9.81; total_mass = total_mass + masses[i] end
    for i, degree in ipairs(free) do free_masses[i] = masses[owners[degree][1]] end
    local modes, lines = {}, {}
    line(lines, 'vibration', name, 'mass', real(total_mass), 'iterations', iterations)
    for mode = 1, mode_count do
        local vector = {}
        for i = 1, #free do vector[i] = 1.0 end
        for _ = 1, iterations do
            for _, previous in ipairs(modes) do
                local beta = 0.0
                for i = 1, #free do beta = beta + previous[i] * free_masses[i] * vector[i] end
                for i = 1, #free do vector[i] = vector[i] - beta * previous[i] end
            end
            local right = {}
            for i = 1, #free do right[i] = free_masses[i] * vector[i] end
            local solution, norm = solver.solve(final_system.lower, right), 0.0
            for i = 1, #free do norm = norm + free_masses[i] * solution[i] * solution[i] end
            norm = math.sqrt(norm)
            for i = 1, #free do vector[i] = solution[i] / norm end
        end
        modes[#modes + 1] = vector
        local numerator, denominator = 0.0, 0.0
        for i = 1, #free do
            local product = 0.0
            for j = 1, #free do product = product + final_system.free_matrix[i][j] * vector[j] end
            numerator = numerator + vector[i] * product
            denominator = denominator + free_masses[i] * vector[i] * vector[i]
        end
        local frequency = math.sqrt(1000 * (numerator / denominator)) / (2 * design.PI)
        line(lines, 'mode', mode, 'frequency', real(frequency), 'period', real(1 / frequency))
        local peak = 1
        for i = 2, #vector do if math.abs(vector[i]) > math.abs(vector[peak]) then peak = i end end
        local normalized = assembly.zeros(nd)
        for i, degree in ipairs(free) do normalized[degree] = vector[i] / vector[peak] end
        for i, node in ipairs(nodes) do line(lines, 'node', node.identifier, real(normalized[node_dofs[i][1]]), real(normalized[node_dofs[i][2]])) end
    end
    return lines
end
local Canvas = {}
Canvas.__index = Canvas
function Canvas.new(horizontal, vertical)
    local x0, x1, y0, y1 = nodes[1].x, nodes[1].x, nodes[1].y, nodes[1].y
    for _, node in ipairs(nodes) do x0, x1, y0, y1 = math.min(x0, node.x), math.max(x1, node.x), math.min(y0, node.y), math.max(y1, node.y) end
    local width, height = math.floor((x1 - x0) / horizontal + 0.5) + 5, math.floor((y1 - y0) / vertical + 0.5) + 5
    local grid = {}
    for row = 1, height do grid[row] = {}; for column = 1, width do grid[row][column] = ' ' end end
    return setmetatable({x0 = x0, y1 = y1, horizontal = horizontal, vertical = vertical, width = width, height = height, grid = grid}, Canvas)
end
function Canvas:position(x, y) return {math.floor((x - self.x0) / self.horizontal + 0.5) + 2, math.floor((self.y1 - y) / self.vertical + 0.5) + 2} end
function Canvas:put(column, row, character)
    if column >= 0 and column < self.width and row >= 0 and row < self.height then self.grid[row + 1][column + 1] = character end
end
function Canvas:segment(first, last, character)
    local c, r, c1, r1 = first[1], first[2], last[1], last[2]
    local dc, dr, sc, sr = math.abs(c1 - c), -math.abs(r1 - r), c < c1 and 1 or -1, r < r1 and 1 or -1
    local err = dc + dr
    while true do
        self:put(c, r, character)
        if c == c1 and r == r1 then break end
        local twice = 2 * err
        if twice >= dr then err, c = err + dr, c + sc end
        if twice <= dc then err, r = err + dc, r + sr end
    end
end
function Canvas:framed()
    local border, lines = '+' .. string.rep('-', self.width) .. '+', {}
    lines[#lines + 1] = border
    for _, row in ipairs(self.grid) do lines[#lines + 1] = '|' .. table.concat(row) .. '|' end
    lines[#lines + 1] = border
    return lines
end
local function drawing_report()
    local lines = {}
    for _, drawing in ipairs(settings.drawing) do
        local name, magnification, horizontal, vertical = table.unpack(drawing)
        local result, canvas, original, deformed = results[name], Canvas.new(horizontal, vertical), {}, {}
        for i, node in ipairs(nodes) do
            original[i] = canvas:position(node.x, node.y)
            local dofs = node_dofs[i]
            deformed[i] = canvas:position(node.x + magnification * result.displacement[dofs[1]], node.y + magnification * result.displacement[dofs[2]])
        end
        for _, member in ipairs(members) do canvas:segment(original[member.start], original[member.finish], '.') end
        for _, position in ipairs(original) do canvas:put(position[1], position[2], '+') end
        for _, member in ipairs(members) do canvas:segment(deformed[member.start], deformed[member.finish], '*') end
        for _, position in ipairs(deformed) do canvas:put(position[1], position[2], 'o') end
        line(lines, 'drawing', name, 'magnification', magnification, 'columns', canvas.width, 'rows', canvas.height)
        append(lines, canvas:framed())
    end
    local horizontal, vertical = table.unpack(settings.utilization_map)
    local canvas, positions = Canvas.new(horizontal, vertical), {}
    for i, node in ipairs(nodes) do positions[i] = canvas:position(node.x, node.y) end
    for i, member in ipairs(members) do canvas:segment(positions[member.start], positions[member.finish], governing[i] >= 1 and '#' or tostring(math.floor(10 * governing[i]))) end
    for _, position in ipairs(positions) do canvas:put(position[1], position[2], 'o') end
    line(lines, 'utilization_map columns', canvas.width, 'rows', canvas.height)
    append(lines, canvas:framed())
    return lines
end
local function csv_reports()
    local displacements, forces, reactions = {'case,node,dx,dy'}, {'case,member,force,stress,utilization'}, {'case,node,rx,ry'}
    for _, item in ipairs(result_order) do
        local name = item[2]
        local result = results[name]
        for i, node in ipairs(nodes) do
            local dofs = node_dofs[i]
            displacements[#displacements + 1] = table.concat({name, node.identifier, real(result.displacement[dofs[1]]), real(result.displacement[dofs[2]])}, ',')
        end
        for i, member in ipairs(members) do forces[#forces + 1] = table.concat({name, member.identifier, real(result.forces[i] / 1000), real(result.forces[i] / properties[i].area), real(design.utilization(result.forces[i], properties[i], geometry[i]))}, ',') end
        for _, support in ipairs(model.supports) do
            local dofs = node_dofs[support.node]
            reactions[#reactions + 1] = table.concat({name, nodes[support.node].identifier, real(result.reactions[dofs[1]] / 1000), real(result.reactions[dofs[2]] / 1000)}, ',')
        end
    end
    return displacements, forces, reactions
end
local history = design_sections()
local displacement_lines, force_lines, reaction_lines = csv_reports()
local outputs = {{'analysis.txt', analysis_report()}, {'displacements.csv', displacement_lines}, {'member_forces.csv', force_lines}, {'reactions.csv', reaction_lines},
    {'design.txt', design_report(history)}, {'influence.txt', influence_report()}, {'drawing.txt', drawing_report()}, {'vibration.txt', vibration_report()}}
for _, output in ipairs(outputs) do
    local file = assert(io.open('output/' .. output[1], 'wb'))
    for _, text in ipairs(output[2]) do file:write(text, '\n') end
    file:close()
end
