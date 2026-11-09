local factors = require('factors')
local M = {}
local function keys(set)
    local result = {}
    for v in pairs(set) do result[#result + 1] = v end
    table.sort(result)
    return result
end
function M.interaction_graph(initial)
    local graph = {}
    for _, factor in ipairs(initial) do
        for _, v in ipairs(factor.variables) do graph[v] = graph[v] or {} end
        for i = 1, #factor.variables do for j = i + 1, #factor.variables do local a, b = factor.variables[i], factor.variables[j]; graph[a][b], graph[b][a] = true, true end end
    end
    return graph
end
function M.make_plan(initial, eliminate, method, given_order, sizes)
    local graph, remaining, ranks = M.interaction_graph(initial), {}, {}
    for _, v in ipairs(eliminate) do remaining[v] = true end
    for rank, v in ipairs(given_order) do ranks[v] = rank end
    local plan = {steps = {}, maximum = 0, total = 0}
    while next(remaining) do
        local chosen, chosen_fill, chosen_degree
        for _, v in ipairs(keys(remaining)) do
            local neighbors, fill = keys(graph[v]), 0
            for i = 1, #neighbors do for j = i + 1, #neighbors do if not graph[neighbors[i]][neighbors[j]] then fill = fill + 1 end end end
            local better = not chosen
            if chosen then
                if method == 'GIVEN' then better = ranks[v] < ranks[chosen]
                else better = fill < chosen_fill or fill == chosen_fill and #neighbors < chosen_degree end
            end
            if better then chosen, chosen_fill, chosen_degree = v, fill, #neighbors end
        end
        local neighbors, scope = keys(graph[chosen]), {chosen}
        for _, v in ipairs(neighbors) do scope[#scope + 1] = v end
        table.sort(scope)
        local size = factors.entry_count(scope, sizes)
        plan.steps[#plan.steps + 1] = {variable = chosen, fill = chosen_fill, scope = scope, size = size}
        plan.maximum, plan.total = math.max(plan.maximum, size), plan.total + size
        for i = 1, #neighbors do for j = i + 1, #neighbors do local a, b = neighbors[i], neighbors[j]; graph[a][b], graph[b][a] = true, true end end
        for _, v in ipairs(neighbors) do graph[v][chosen] = nil end
        graph[chosen], remaining[chosen] = nil, nil
    end
    return plan
end
function M.execute(initial, plan, sizes, maximize)
    local active, products = {}, {}
    for _, factor in ipairs(initial) do active[#active + 1] = factor end
    for _, step in ipairs(plan.steps) do
        local selected, remaining = {}, {}
        for _, factor in ipairs(active) do
            local contains = false
            for _, v in ipairs(factor.variables) do if v == step.variable then contains = true end end
            if contains then selected[#selected + 1] = factor else remaining[#remaining + 1] = factor end
        end
        local product = factors.multiply(selected, sizes)
        remaining[#remaining + 1] = product:eliminate(step.variable, maximize)
        active = remaining
        if maximize then products[#products + 1] = {variable = step.variable, factor = product} end
    end
    return factors.multiply(active, sizes), products
end
function M.traceback(products, sizes)
    local assignment = {}
    for i = #products, 1, -1 do
        local product = products[i]
        local state, maximum = 1, -math.huge
        for candidate = 1, sizes[product.variable] do
            assignment[product.variable] = candidate
            local value = product.factor:value(assignment)
            if value > maximum then maximum, state = value, candidate end
        end
        assignment[product.variable] = state
    end
    return assignment
end
return M
