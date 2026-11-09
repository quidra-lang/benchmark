package.path = 'Lua/?.lua;' .. package.path
local network_io = require('network_io')
local learning = require('learning')
local factors = require('factors')
local elimination = require('elimination')
local sampling = require('sampling')
local network, samples, queries, params = network_io.read_inputs()
local names, states, parents, expert = network.names, network.states, network.parents, network.expert
local n, variables, sizes = #names, {}, {}
for v = 1, n do variables[v], sizes[v] = v, #states[v] end
local function real(value)
    local text = string.format('%.4f', value)
    return text == '-0.0000' and '0.0000' or text
end
local function yes(value) return value and 'yes' or 'no' end
local function copy(values)
    local result = {}
    for key, value in pairs(values) do result[key] = value end
    return result
end
local function keys(set)
    local result = {}
    for key in pairs(set) do result[#result + 1] = key end
    table.sort(result)
    return result
end
local function as_set(values)
    local result = {}
    for _, value in ipairs(values) do result[value] = true end
    return result
end
local function union(...)
    local result = {}
    for i = 1, select('#', ...) do for _, v in ipairs(select(i, ...)) do result[v] = true end end
    return keys(result)
end
local function without(values, excluded)
    local result = {}
    for _, v in ipairs(values) do if excluded[v] == nil then result[#result + 1] = v end end
    return result
end
local function append(destination, source) for _, value in ipairs(source) do destination[#destination + 1] = value end end
local function line(lines, ...) lines[#lines + 1] = table.concat({...}, ' ') end
local function sequence(values)
    local result = {}
    for _, v in ipairs(values) do result[#result + 1] = names[v] end
    return #result == 0 and '-' or table.concat(result, ' ')
end
local function assignment_text(assignment, scope)
    local result = {}
    for _, v in ipairs(scope or keys(assignment)) do result[#result + 1] = names[v] .. '=' .. states[v][assignment[v]] end
    return #result == 0 and '-' or table.concat(result, ' ')
end
local children = {}
for v = 1, n do children[v] = {} end
for child = 1, n do for _, parent in ipairs(parents[child]) do children[parent][#children[parent] + 1] = child end end
local function closure(initial, links)
    local reached, pending = as_set(initial), copy(initial)
    while #pending > 0 do
        local v = table.remove(pending)
        for _, neighbor in ipairs(links[v]) do if not reached[neighbor] then reached[neighbor] = true; pending[#pending + 1] = neighbor end end
    end
    return keys(reached)
end
local topological, selected, depths, ancestors, descendants, spouses, blankets = {}, {}, {}, {}, {}, {}, {}
while #topological < n do
    for v = 1, n do
        if not selected[v] then
            local ready = true
            for _, parent in ipairs(parents[v]) do if not selected[parent] then ready = false end end
            if ready then topological[#topological + 1] = v; selected[v] = true; break end
        end
    end
end
for _, v in ipairs(topological) do
    depths[v] = 0
    for _, parent in ipairs(parents[v]) do depths[v] = math.max(depths[v], depths[parent] + 1) end
end
for v = 1, n do
    ancestors[v], descendants[v] = closure(parents[v], parents), closure(children[v], children)
    local immediate, spouse_set = as_set(union(parents[v], children[v])), {}
    for _, child in ipairs(children[v]) do for _, parent in ipairs(parents[child]) do if parent ~= v and not immediate[parent] then spouse_set[parent] = true end end end
    spouses[v] = keys(spouse_set)
    blankets[v] = union(parents[v], children[v], spouses[v])
end
local counts, learned, cpts, likelihoods, parameter_counts, cpt_factors = {}, {}, {}, {}, {}, {}
for v = 1, n do
    counts[v] = learning.count_samples(v, parents[v], samples, sizes)
    learned[v] = learning.learn(counts[v], params.alpha)
    cpts[v] = params.sources[v] == 'GIVEN' and expert[v] or learned[v]
    likelihoods[v] = learning.log_likelihood(counts[v], cpts[v])
    parameter_counts[v] = learning.parameter_count(counts[v])
    cpt_factors[v] = factors.cpt_factor(v, parents[v], cpts[v], sizes)
end
local random, family_scores = sampling.generator(params.seed), {}
local function parse_evidence(fields, first, last)
    local result = {map = {}, order = {}}
    for i = first or 1, last or #fields do
        local name, state = fields[i]:match('^([^=]+)=(.+)$')
        local v = network.index[name]
        local s
        for index, candidate in ipairs(states[v]) do if candidate == state then s = index end end
        result.map[v] = s
        result.order[#result.order + 1] = {v, s}
    end
    return result
end
local function query_parts(fields, last)
    local query, separator = {}, nil
    last = last or #fields
    for i = 1, last do if fields[i] == '|' then separator = i; break end end
    for i = 1, separator and separator - 1 or last do query[#query + 1] = network.index[fields[i]] end
    return query, parse_evidence(fields, separator and separator + 1 or last + 1, last)
end
local function plans(initial, eliminate)
    return {MINFILL = elimination.make_plan(initial, eliminate, 'MINFILL', params.order, sizes), GIVEN = elimination.make_plan(initial, eliminate, 'GIVEN', params.order, sizes)}
end
local function sum_result(initial, plan, query)
    local factor = elimination.execute(initial, plan, sizes)
    local probability = learning.total(factor.values)
    local values, marginals = {}, {}
    for _, v in ipairs(query) do marginals[v] = {}; for state = 1, sizes[v] do marginals[v][state] = 0.0 end end
    local index = 0
    for assignment in factors.assignments(factor.variables, sizes) do
        index = index + 1
        local posterior = factor.values[index] / probability
        values[index] = posterior
        for _, v in ipairs(query) do marginals[v][assignment[v]] = marginals[v][assignment[v]] + posterior end
    end
    return factors.new(factor.variables, values, sizes), probability, marginals
end
local function posterior(query, evidence)
    local relevant = closure(union(query, keys(evidence)), parents)
    local excluded = copy(evidence)
    for _, v in ipairs(query) do excluded[v] = true end
    local eliminate, initial = without(relevant, excluded), {}
    for _, v in ipairs(relevant) do initial[#initial + 1] = cpt_factors[v]:reduced(evidence) end
    local orders = plans(initial, eliminate)
    local distribution, probability, marginals = sum_result(initial, orders[params.method], query)
    return {relevant = relevant, eliminate = eliminate, initial = initial, plans = orders, distribution = distribution, probability = probability, marginals = marginals}
end
local function joint(assignment, scope)
    local probability = 1.0
    for _, v in ipairs(scope) do probability = probability * cpts[v][learning.parent_row(parents[v], assignment, sizes)][assignment[v]] end
    return probability
end
local function query_enumeration(result, query, evidence)
    local free = without(result.relevant, evidence)
    local count = factors.entry_count(free, sizes)
    if count > params.limit then return count, 'skipped' end
    local ordered_query, values = copy(query), {}
    table.sort(ordered_query)
    for index = 1, factors.entry_count(ordered_query, sizes) do values[index] = 0.0 end
    for assignment in factors.assignments(free, sizes) do
        for v, state in pairs(evidence) do assignment[v] = state end
        local row = learning.parent_row(ordered_query, assignment, sizes)
        values[row] = values[row] + joint(assignment, result.relevant)
    end
    local probability = learning.total(values)
    local agreed = math.abs(math.log(probability) - math.log(result.probability)) <= 1e-9
    for i, value in ipairs(values) do agreed = agreed and math.abs(value / probability - result.distribution.values[i]) <= 1e-9 end
    return count, agreed and 'agree' or 'disagree'
end
local function elimination_lines(result, agreement, count, enumeration)
    local lines = {}
    line(lines, 'relevant', sequence(result.relevant)); line(lines, 'pruned', sequence(without(variables, as_set(result.relevant)))); line(lines, 'eliminate', sequence(result.eliminate))
    for _, method in ipairs({'MINFILL', 'GIVEN'}) do
        local plan = result.plans[method]
        line(lines, 'order', method:lower())
        for _, step in ipairs(plan.steps) do line(lines, 'step', names[step.variable], 'fill', step.fill, 'scope', sequence(step.scope), 'entries', step.size) end
        line(lines, 'cost max', plan.maximum, 'total', plan.total)
    end
    line(lines, 'used', params.method:lower()); line(lines, 'orders_agree', yes(agreement)); line(lines, 'enumeration', count, enumeration)
    return lines
end
local function marginal_lines(prefix, query, marginals)
    local lines = {}
    for _, v in ipairs(query) do
        local parts = {prefix, names[v]}
        for state, probability in ipairs(marginals[v]) do parts[#parts + 1] = states[v][state]; parts[#parts + 1] = real(probability) end
        lines[#lines + 1] = table.concat(parts, ' ')
    end
    return lines
end
local function answer_query(query, evidence)
    local result = posterior(query, evidence.map)
    local lines = {'log_evidence ' .. real(math.log(result.probability))}
    if #evidence.order > 0 then
        local conflict = 0.0
        for _, item in ipairs(evidence.order) do conflict = conflict + math.log(posterior({}, {[item[1]] = item[2]}).probability) end
        line(lines, 'conflict', real(conflict - math.log(result.probability)))
    end
    if #query >= 2 then
        local index = 0
        for assignment in factors.assignments(result.distribution.variables, sizes) do index = index + 1; line(lines, 'joint', assignment_text(assignment), real(result.distribution.values[index])) end
    end
    append(lines, marginal_lines('marginal', query, result.marginals))
    for _, item in ipairs(evidence.order) do
        local reduced = copy(evidence.map)
        reduced[item[1]] = nil
        local without_marginal, shift = posterior(query, reduced).marginals, 0.0
        for _, v in ipairs(query) do for state = 1, sizes[v] do shift = math.max(shift, math.abs(result.marginals[v][state] - without_marginal[v][state])) end end
        line(lines, 'drop', names[item[1]] .. '=' .. states[item[1]][item[2]], 'shift', real(shift))
    end
    local first, first_z = sum_result(result.initial, result.plans.MINFILL, query)
    local second, second_z = sum_result(result.initial, result.plans.GIVEN, query)
    local agreement = math.abs(math.log(first_z) - math.log(second_z)) <= 1e-9
    for i, value in ipairs(first.values) do agreement = agreement and math.abs(value - second.values[i]) <= 1e-9 end
    local count, enumeration = query_enumeration(result, query, evidence.map)
    return lines, elimination_lines(result, agreement, count, enumeration)
end
local function equal_assignments(a, b)
    for v = 1, n do if a[v] ~= b[v] then return false end end
    return true
end
local function answer_mpe(evidence)
    local initial = {}
    for _, factor in ipairs(cpt_factors) do initial[#initial + 1] = factor:reduced(evidence.map) end
    local eliminate = without(variables, evidence.map)
    local orders, outcomes = plans(initial, eliminate), {}
    for _, method in ipairs({'MINFILL', 'GIVEN'}) do
        local factor, products = elimination.execute(initial, orders[method], sizes, true)
        local assignment = elimination.traceback(products, sizes)
        for v, state in pairs(evidence.map) do assignment[v] = state end
        outcomes[method] = {maximum = factor.values[1], assignment = assignment}
    end
    local outcome = outcomes[params.method]
    local probability = #evidence.order > 0 and posterior({}, evidence.map).probability or 1.0
    local lines = {'assignment ' .. assignment_text(outcome.assignment), 'log_joint ' .. real(math.log(outcome.maximum)), 'log_evidence ' .. real(math.log(probability)), 'posterior ' .. real(outcome.maximum / probability)}
    for _, v in ipairs(eliminate) do
        local rest = without(eliminate, {[v] = true})
        local plan = elimination.make_plan(initial, rest, params.method, params.order, sizes)
        local factor = elimination.execute(initial, plan, sizes, true)
        local alternative
        for state = 1, sizes[v] do if state ~= outcome.assignment[v] and (not alternative or factor.values[state] > factor.values[alternative]) then alternative = state end end
        line(lines, 'margin', names[v], states[v][alternative], real(math.log(outcome.maximum) - math.log(factor.values[alternative])))
    end
    local first, second = outcomes.MINFILL, outcomes.GIVEN
    local agreement = equal_assignments(first.assignment, second.assignment) and math.abs(math.log(first.maximum) - math.log(second.maximum)) <= 1e-9
    local count, enumeration = factors.entry_count(eliminate, sizes), 'skipped'
    if count <= params.limit then
        local best, best_assignment = -1.0, nil
        for assignment in factors.assignments(eliminate, sizes) do
            for v, state in pairs(evidence.map) do assignment[v] = state end
            local current = joint(assignment, variables)
            if current > best then best, best_assignment = current, assignment end
        end
        enumeration = equal_assignments(best_assignment, outcome.assignment) and math.abs(math.log(best) - math.log(outcome.maximum)) <= 1e-9 and 'agree' or 'disagree'
    end
    return lines, elimination_lines({relevant = variables, eliminate = eliminate, plans = orders}, agreement, count, enumeration)
end
local function answer_sample(number, query, evidence, checkpoints)
    local exact = posterior(query, evidence.map).marginals
    local lines, csv, weights, checkpoint_set = marginal_lines('exact', query, exact), {}, {}, as_set(checkpoints)
    for _, v in ipairs(query) do weights[v] = {}; for state = 1, sizes[v] do weights[v][state] = 0.0 end end
    local weight, squared_weight = 0.0, 0.0
    for index = 1, checkpoints[#checkpoints] do
        local sample, current = sampling.weighted_sample(topological, parents, cpts, sizes, evidence.map, random)
        weight, squared_weight = weight + current, squared_weight + current * current
        for _, v in ipairs(query) do weights[v][sample[v]] = weights[v][sample[v]] + current end
        if checkpoint_set[index] then
            local maximum_error = 0.0
            for _, v in ipairs(query) do
                for state = 1, sizes[v] do
                    local estimate, probability = weights[v][state] / weight, exact[v][state]
                    local error = math.abs(estimate - probability)
                    maximum_error = math.max(maximum_error, error)
                    csv[#csv + 1] = table.concat({number, index, names[v], states[v][state], real(estimate), real(probability), real(error)}, ',')
                end
            end
            line(lines, 'after', index, 'weight', real(weight), 'ess', real(weight * weight / squared_weight), 'max_error', real(maximum_error))
        end
    end
    return lines, csv
end
local function answer_predict(v)
    local confusion, likelihood = {}, 0.0
    for state = 1, sizes[v] do confusion[state] = {}; for predicted = 1, sizes[v] do confusion[state][predicted] = 0 end end
    for _, sample in ipairs(samples) do
        local assignment, values = copy(sample), {}
        for state = 1, sizes[v] do
            assignment[v] = state
            local probability = cpts[v][learning.parent_row(parents[v], assignment, sizes)][state]
            for _, child in ipairs(children[v]) do probability = probability * cpts[child][learning.parent_row(parents[child], assignment, sizes)][assignment[child]] end
            values[state] = probability
        end
        local denominator, predicted = learning.total(values), 1
        for state = 1, sizes[v] do values[state] = values[state] / denominator; if values[state] > values[predicted] then predicted = state end end
        local actual = sample[v]
        confusion[actual][predicted] = confusion[actual][predicted] + 1
        likelihood = likelihood + math.log(values[actual])
    end
    local correct = 0
    for state = 1, sizes[v] do correct = correct + confusion[state][state] end
    local lines = {'blanket ' .. sequence(blankets[v]), 'accuracy ' .. correct .. '/' .. #samples .. ' ' .. real(correct / #samples), 'log_loss ' .. real(-likelihood / #samples), 'predicted ' .. table.concat(states[v], ' ')}
    for state = 1, sizes[v] do line(lines, 'actual', states[v][state], table.concat(confusion[state], ' ')) end
    return lines
end

local function reachable(x, z)
    local x_set, z_set, ancestor_set = as_set(x), as_set(z), as_set(closure(z, parents))
    local pending, visited, head = {}, {}, 1
    local function visit(v, direction)
        local key = v .. ':' .. direction
        if not visited[key] then visited[key] = true; pending[#pending + 1] = {v, direction} end
    end
    for _, v in ipairs(x) do visit(v, 'up') end
    while head <= #pending do
        local position = pending[head]
        head = head + 1
        local v, direction = position[1], position[2]
        if direction == 'up' and not z_set[v] then
            for _, parent in ipairs(parents[v]) do visit(parent, 'up') end
            for _, child in ipairs(children[v]) do visit(child, 'down') end
        elseif direction == 'down' then
            if not z_set[v] then for _, child in ipairs(children[v]) do visit(child, 'down') end end
            if ancestor_set[v] then for _, parent in ipairs(parents[v]) do visit(parent, 'up') end end
        end
    end
    local result = {}
    for _, position in ipairs(pending) do local v = position[1]; if not z_set[v] and not x_set[v] then result[v] = true end end
    return keys(result)
end
local function mutual_information(x, y, z)
    local scope, xz, yz, ordered_z = union(x, y, z), union(x, z), union(y, z), copy(z)
    table.sort(ordered_z)
    local counts, xz_counts, yz_counts, z_counts, representatives = {}, {}, {}, {}, {}
    for _, sample in ipairs(samples) do
        local index = learning.parent_row(scope, sample, sizes)
        counts[index], representatives[index] = (counts[index] or 0) + 1, sample
        local a, b, c = learning.parent_row(xz, sample, sizes), learning.parent_row(yz, sample, sizes), learning.parent_row(ordered_z, sample, sizes)
        xz_counts[a], yz_counts[b], z_counts[c] = (xz_counts[a] or 0) + 1, (yz_counts[b] or 0) + 1, (z_counts[c] or 0) + 1
    end
    local information = 0.0
    for _, index in ipairs(keys(counts)) do
        local assignment, observed = representatives[index], counts[index]
        local nxz, nyz, nz = xz_counts[learning.parent_row(xz, assignment, sizes)], yz_counts[learning.parent_row(yz, assignment, sizes)], z_counts[learning.parent_row(ordered_z, assignment, sizes)]
        information = information + (observed / #samples) * math.log((observed * nz + 0.0) / (nxz * nyz + 0.0))
    end
    return information, 2 * #samples * information, (factors.entry_count(x, sizes) - 1) * (factors.entry_count(y, sizes) - 1) * factors.entry_count(z, sizes)
end
local function disjoint(a, b)
    local set = as_set(b)
    for _, v in ipairs(a) do if set[v] then return false end end
    return true
end
local function answer_dsep(groups)
    local x, y, z = groups[1], groups[2], groups[3] or {}
    local reached = reachable(x, z)
    local information, statistic, degrees = mutual_information(x, y, z)
    return {'result ' .. (disjoint(reached, y) and 'separated' or 'connected'), 'reachable ' .. sequence(reached), 'data cmi ' .. real(information) .. ' g2 ' .. real(statistic) .. ' df ' .. degrees}
end
local function answer_blanket(v)
    local rest = without(variables, as_set(union({v}, blankets[v])))
    return {'parents ' .. sequence(parents[v]), 'children ' .. sequence(children[v]), 'spouses ' .. sequence(spouses[v]), 'blanket ' .. sequence(blankets[v]), 'rest ' .. sequence(rest), 'rest_separated ' .. yes(disjoint(reachable({v}, blankets[v]), rest))}
end
local function path(start, finish, ignored_a, ignored_b)
    local previous, pending, head = {[start] = 0}, {start}, 1
    while head <= #pending do
        local v = pending[head]
        head = head + 1
        for _, child in ipairs(children[v]) do
            if not (v == ignored_a and child == ignored_b) and previous[child] == nil then
                previous[child] = v
                if child == finish then
                    local result, current = {}, child
                    while current ~= 0 do table.insert(result, 1, current); current = previous[current] end
                    return result
                end
                pending[#pending + 1] = child
            end
        end
    end
    return nil
end
local function score(v, parent_list)
    local ordered = copy(parent_list)
    table.sort(ordered)
    local key = v .. ':' .. table.concat(ordered, ',')
    if family_scores[key] == nil then family_scores[key] = learning.family_score(v, ordered, samples, sizes, params.alpha) end
    return family_scores[key]
end
local function answer_edge(operation, x, y)
    local exists = as_set(parents[y])[x]
    if operation == 'ADD' and exists then return {'result exists'} end
    if operation ~= 'ADD' and not exists then return {'result missing'} end
    local cycle
    if operation == 'ADD' then
        local found = path(y, x)
        if found then cycle = {x}; append(cycle, found) end
    elseif operation == 'REVERSE' then
        local found = path(x, y, x, y)
        if found then cycle = {y}; append(cycle, found) end
    end
    if cycle then
        local cycle_names = {}
        for _, v in ipairs(cycle) do cycle_names[#cycle_names + 1] = names[v] end
        return {'result cycle ' .. table.concat(cycle_names, ' -> ')}
    end
    local before_y = score(y, parents[y])
    local changed_y = operation == 'ADD' and union(parents[y], {x}) or without(parents[y], {[x] = true})
    local after_y = score(y, changed_y)
    local change, lines = after_y - before_y, {'result ok', 'family ' .. names[y] .. ' before ' .. real(before_y) .. ' after ' .. real(after_y)}
    if operation == 'REVERSE' then
        local before_x, after_x = score(x, parents[x]), score(x, union(parents[x], {y}))
        change = (after_y - before_y) + (after_x - before_x)
        line(lines, 'family', names[x], 'before', real(before_x), 'after', real(after_x))
    end
    line(lines, 'delta', real(change), change > 0 and 'improves' or 'worsens')
    return lines
end
local function real_values(values)
    local result = {}
    for _, value in ipairs(values) do result[#result + 1] = real(value) end
    return table.concat(result, ' ')
end
local function cpt_blocks()
    local blocks = {}
    for v = 1, n do
        local source, lines = params.sources[v], {}
        line(lines, 'variable', names[v], 'source', source); line(lines, 'states', table.concat(states[v], ' ')); line(lines, 'parents', sequence(parents[v]))
        local row = 0
        for assignment in factors.assignments(parents[v], sizes) do
            row = row + 1
            line(lines, 'row', assignment_text(assignment, parents[v]), 'counts', table.concat(counts[v][row], ' '), 'probs', real_values(cpts[v][row]))
        end
        line(lines, 'loglik', real(likelihoods[v]), 'parameters', parameter_counts[v], 'bic', real(likelihoods[v] - parameter_counts[v] * math.log(#samples) / 2))
        local marginal, frequencies = posterior({v}, {}).marginals[v], {}
        for state = 1, sizes[v] do
            local count = 0
            for _, count_row in ipairs(counts[v]) do count = count + count_row[state] end
            frequencies[state] = count / #samples
        end
        line(lines, 'marginal model', real_values(marginal), 'data', real_values(frequencies))
        if source == 'LEARNED' then
            local difference = '-'
            if expert[v] then
                local maximum = 0.0
                for r, learned_row in ipairs(learned[v]) do for state, probability in ipairs(learned_row) do maximum = math.max(maximum, math.abs(probability - expert[v][r][state])) end end
                difference = real(maximum)
            end
            line(lines, 'given_difference', difference)
        end
        blocks[#blocks + 1] = lines
    end
    local likelihood, parameters = learning.total(likelihoods), 0
    for _, count in ipairs(parameter_counts) do parameters = parameters + count end
    blocks[#blocks + 1] = {'network samples ' .. #samples .. ' pseudocount ' .. real(params.alpha) .. ' loglik ' .. real(likelihood) .. ' parameters ' .. parameters .. ' bic ' .. real(likelihood - parameters * math.log(#samples) / 2)}
    return blocks
end
local function structure_summary()
    local orders = plans(cpt_factors, variables)
    local widths = {}
    for _, method in ipairs({'MINFILL', 'GIVEN'}) do local maximum = 0; for _, step in ipairs(orders[method].steps) do maximum = math.max(maximum, #step.scope) end; widths[method] = maximum - 1 end
    local graph, moral_edges, edges, roots, leaves = elimination.interaction_graph(cpt_factors), 0, 0, {}, {}
    for v = 1, n do
        edges = edges + #parents[v]
        if #parents[v] == 0 then roots[#roots + 1] = v end
        if #children[v] == 0 then leaves[#leaves + 1] = v end
        for _ in pairs(graph[v]) do moral_edges = moral_edges + 1 end
    end
    local lines = {}
    line(lines, 'variables', n, 'edges', edges); line(lines, 'topological_order', sequence(topological)); line(lines, 'roots', sequence(roots)); line(lines, 'leaves', sequence(leaves))
    line(lines, 'moral_edges', moral_edges // 2, 'width minfill', widths.MINFILL, 'given', widths.GIVEN)
    for v = 1, n do line(lines, 'variable', names[v], 'states', sizes[v], 'parents', #parents[v], 'children', #children[v], 'depth', depths[v], 'ancestors', #ancestors[v], 'descendants', #descendants[v], 'blanket', #blankets[v]) end
    return lines
end
local answer_blocks, elimination_blocks, structure_blocks = {}, {}, {structure_summary()}
local csv = {'query,samples,variable,state,estimate,exact,abs_error'}
for number, source in ipairs(queries) do
    local fields = {}
    for field in source:gmatch('%S+') do fields[#fields + 1] = field end
    local kind = table.remove(fields, 1)
    local heading = 'query ' .. number .. ' ' .. source
    if kind == 'QUERY' then
        local query, evidence = query_parts(fields)
        local answer, steps = answer_query(query, evidence)
        table.insert(answer, 1, heading); table.insert(steps, 1, heading)
        answer_blocks[#answer_blocks + 1], elimination_blocks[#elimination_blocks + 1] = answer, steps
    elseif kind == 'MPE' then
        local answer, steps = answer_mpe(parse_evidence(fields))
        table.insert(answer, 1, heading); table.insert(steps, 1, heading)
        answer_blocks[#answer_blocks + 1], elimination_blocks[#elimination_blocks + 1] = answer, steps
    elseif kind == 'SAMPLE' then
        local separator
        for i, field in ipairs(fields) do if field == 'COUNTS' then separator = i end end
        local query, evidence = query_parts(fields, separator - 1)
        local checkpoints = {}
        for i = separator + 1, #fields do checkpoints[#checkpoints + 1] = tonumber(fields[i]) end
        local answer, rows = answer_sample(number, query, evidence, checkpoints)
        table.insert(answer, 1, heading); answer_blocks[#answer_blocks + 1] = answer; append(csv, rows)
    elseif kind == 'PREDICT' then
        local answer = answer_predict(network.index[fields[1]])
        table.insert(answer, 1, heading); answer_blocks[#answer_blocks + 1] = answer
    else
        local answer
        if kind == 'DSEP' then
            local groups = {{}}
            for _, field in ipairs(fields) do if field == '|' then groups[#groups + 1] = {} else groups[#groups][#groups[#groups] + 1] = network.index[field] end end
            answer = answer_dsep(groups)
        elseif kind == 'BLANKET' then answer = answer_blanket(network.index[fields[1]])
        else answer = answer_edge(fields[1], network.index[fields[2]], network.index[fields[3]]) end
        table.insert(answer, 1, heading); structure_blocks[#structure_blocks + 1] = answer
    end
end
local function write_blocks(filename, blocks)
    local parts = {}
    for _, block in ipairs(blocks) do parts[#parts + 1] = table.concat(block, '\n') end
    local file = assert(io.open('output/' .. filename, 'wb'))
    if #parts > 0 then file:write(table.concat(parts, '\n\n'), '\n') end
    file:close()
end
write_blocks('cpts.txt', cpt_blocks())
write_blocks('structure.txt', structure_blocks)
write_blocks('answers.txt', answer_blocks)
write_blocks('elimination.txt', elimination_blocks)
write_blocks('sampling.csv', {csv})
