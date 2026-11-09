local Grid = require("grid_map")
local CBS = {}

function CBS.position(path, time)
    return path[math.min(time + 1, #path)]
end

function CBS.conflicts(paths)
    local horizon, result = 0, {}
    for _, path in ipairs(paths) do horizon = math.max(horizon, #path - 1) end
    for time = 1, horizon do
        for a = 1, #paths do
            for b = a + 1, #paths do
                local current_a, current_b = CBS.position(paths[a], time), CBS.position(paths[b], time)
                if current_a == current_b then
                    result[#result + 1] = {kind = "vertex", time = time, a = a, b = b, cell = current_a}
                elseif current_a == CBS.position(paths[b], time - 1) and current_b == CBS.position(paths[a], time - 1) then
                    result[#result + 1] = {kind = "edge", time = time, a = a, b = b,
                        source = CBS.position(paths[a], time - 1), destination = current_a}
                end
            end
        end
    end
    return result
end

function CBS.split(conflict)
    local source = conflict.cell or conflict.source
    local destination = conflict.cell or conflict.destination
    return {{agent = conflict.a, kind = conflict.kind, source = source, destination = destination, time = conflict.time},
        {agent = conflict.b, kind = conflict.kind, source = destination, destination = source, time = conflict.time}}
end

function CBS.cost(paths, cost_function)
    local soc, makespan = 0, 0
    for _, path in ipairs(paths) do soc, makespan = soc + #path - 1, math.max(makespan, #path - 1) end
    return cost_function == "SOC" and soc or makespan
end

function CBS.node(paths, constraints, number, depth, parent, cost_function)
    return {paths = paths, constraints = constraints, number = number, depth = depth, parent = parent,
        conflicts = CBS.conflicts(paths), cost = CBS.cost(paths, cost_function)}
end

function CBS.less(a, b)
    if a.cost ~= b.cost then return a.cost < b.cost end
    if #a.conflicts ~= #b.conflicts then return #a.conflicts < #b.conflicts end
    return a.number < b.number
end

function CBS.ordered_constraints(node)
    local result = {}
    for index, restrictions in ipairs(node.constraints) do
        for _, item in pairs(restrictions.states) do
            result[#result + 1] = {agent = index, time = item.time, kind = 0, source = item.cell, destination = item.cell}
        end
        for _, item in pairs(restrictions.moves) do
            result[#result + 1] = {agent = index, time = item.time, kind = 1, source = item.source, destination = item.destination}
        end
    end
    table.sort(result, function(a, b)
        if a.agent ~= b.agent then return a.agent < b.agent end
        if a.time ~= b.time then return a.time < b.time end
        if a.kind ~= b.kind then return a.kind < b.kind end
        local ax, ay = Grid.xy(a.source)
        local bx, by = Grid.xy(b.source)
        if ax ~= bx then return ax < bx end
        if ay ~= by then return ay < by end
        ax, ay = Grid.xy(a.destination)
        bx, by = Grid.xy(b.destination)
        if ax ~= bx then return ax < bx end
        return ay < by
    end)
    return result
end

return CBS
