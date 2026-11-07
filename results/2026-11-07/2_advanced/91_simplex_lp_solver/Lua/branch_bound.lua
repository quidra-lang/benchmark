local Q = require("rational")
local function copy(values) return { table.unpack(values) } end
return function(model, limit, solve)
    local stack = { { lower = copy(model.lower), upper = copy(model.upper), depth = 0, branch = "root" } }
    local solves, lines = {}, {}
    local incumbent, objective, status = false, false, false
    local incumbents, pruned, infeasible = 0, 0, 0
    local function better(a, b)
        if model.direction == "maximize" then return a > b end
        return a < b
    end
    while #stack > 0 do
        if #solves == limit then status = "NODE_LIMIT"; break end
        local node = table.remove(stack)
        local number = #solves + 1
        local result = solve(node.lower, node.upper, number)
        solves[#solves + 1] = result
        local outcome
        if result.status == "INFEASIBLE" then outcome, infeasible = "infeasible", infeasible + 1
        elseif result.status == "UNBOUNDED" then outcome, status = "unbounded", "UNBOUNDED"
        elseif objective and not better(result.objective, objective) then outcome, pruned = "pruned", pruned + 1
        else
            local fractional = false
            for j, integer in ipairs(model.integer) do
                if integer and result.solution[j].d ~= 1 then fractional = j; break end
            end
            if not fractional then
                incumbent, objective = copy(result.solution), result.objective
                outcome, incumbents = "incumbent", incumbents + 1
            else
                local value, variable = result.solution[fractional], model.variables[fractional]
                local down, up = Q.floor(value), Q.ceil(value)
                local lower, upper = copy(node.lower), copy(node.upper)
                lower[fractional], upper[fractional] = Q.new(up), Q.new(down)
                stack[#stack + 1] = { lower = lower, upper = copy(node.upper), depth = node.depth + 1,
                    parent = number, branch = variable .. ">=" .. up, parent_value = result.objective }
                stack[#stack + 1] = { lower = copy(node.lower), upper = upper, depth = node.depth + 1,
                    parent = number, branch = variable .. "<=" .. down, parent_value = result.objective }
                outcome = "branch " .. variable .. " " .. value
            end
        end
        local lp = result.status == "OPTIMAL" and tostring(result.objective) or result.status:lower()
        lines[#lines + 1] = string.format("NODE %d depth %d parent %s branch %s lp %s pivots %d action %s",
            number, node.depth, node.parent or "-", node.branch, lp, result.pivots, outcome)
        if status == "UNBOUNDED" then break end
    end
    status = status or (incumbent and "OPTIMAL" or "INFEASIBLE")
    local bound = objective
    if status == "NODE_LIMIT" then
        for i = #stack, 1, -1 do
            local node = stack[i]
            lines[#lines + 1] = string.format("OPEN parent %d branch %s bound %s", node.parent, node.branch, node.parent_value)
            if not bound or better(node.parent_value, bound) then bound = node.parent_value end
        end
    end
    lines[#lines + 1] = string.format("RESULT %s objective %s nodes %d incumbents %d pruned %d infeasible %d open %d bound %s",
        status, objective and tostring(objective) or "-", #solves, incumbents, pruned, infeasible, #stack,
        bound and tostring(bound) or "-")
    return { status = status, objective = objective, solution = incumbent, solves = solves, root = solves[1],
        lines = lines, nodes = #solves }
end
