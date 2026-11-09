local Grid = require("grid_map")
local Low = require("low_level")
local CBS = require("cbs")
local Prioritized = require("prioritized")
local Report = require("report")

local function append(items, value)
    items[#items + 1] = value
end

local function extend(items, values)
    for _, value in ipairs(values) do append(items, value) end
end

local function copy(items)
    local result = {}
    for key, value in pairs(items) do result[key] = value end
    return result
end

local function count(items)
    local result = 0
    for _ in pairs(items) do result = result + 1 end
    return result
end

local function parameters(n)
    local settings = {orders = {{}}, runs = {}, delays = {}}
    for index = 1, n do append(settings.orders[1], index) end
    for line in io.lines("input/params.txt") do
        local f = Grid.words(line)
        local kind = f[1]
        if kind == "HORIZON" then settings.horizon = tonumber(f[2])
        elseif kind == "HL_BUDGET" then settings.hl_budget = tonumber(f[2])
        elseif kind == "LL_BUDGET" then settings.ll_budget = tonumber(f[2])
        elseif kind == "WINDOW" then settings.window, settings.step = tonumber(f[2]), tonumber(f[3])
        elseif kind == "ORDER" then
            local order = {}
            for i = 2, #f do append(order, tonumber(f[i]) + 1) end
            append(settings.orders, order)
        elseif kind == "RUN" then
            append(settings.runs, {name = f[2] .. "-" .. f[3], solver = f[2], cost_function = f[3]})
        elseif kind == "ANIMATE" then settings.animate, settings.frames = f[2], tonumber(f[3])
        else append(settings.delays, {agent = tonumber(f[2]) + 1, start = tonumber(f[3]), duration = tonumber(f[4])}) end
    end
    return settings
end

local function mdd_layers(grid, agent, distances, length, restrictions)
    local layers, valid = {{[agent.start] = true}}, {}
    for time = 1, length do
        local next_layer = {}
        for cell in pairs(layers[time]) do
            for _, destination in ipairs(grid.destinations[cell]) do
                if distances[destination] ~= nil and time + distances[destination] <= length
                    and restrictions:allowed(cell, destination, time) then next_layer[destination] = true end
            end
        end
        layers[time + 1] = next_layer
    end
    valid[length + 1] = {[agent.goal] = true}
    for time = length - 1, 0, -1 do
        local layer = {}
        for source in pairs(layers[time + 1]) do
            for _, destination in ipairs(grid.destinations[source]) do
                if valid[time + 2][destination] and restrictions:allowed(source, destination, time + 1) then
                    layer[source] = true
                    break
                end
            end
        end
        valid[time + 1] = layer
    end
    return valid
end

local function mdd_properties(layers)
    local states, width = 0, 0
    for _, layer in ipairs(layers) do local n = count(layer); states, width = states + n, math.max(width, n) end
    return states, width
end

local function conflict_class(conflict, paths, restrictions, grid, agents, distances, cache)
    local fixed = 0
    for _, index in ipairs({conflict.a, conflict.b}) do
        local length = #paths[index] - 1
        local layers = cache[index]
        if not layers then
            layers = mdd_layers(grid, agents[index], distances[index], length, restrictions[index])
            cache[index] = layers
        end
        local time = conflict.time
        local forced = time > length or (conflict.kind == "vertex" and count(layers[time + 1]) == 1)
            or (conflict.kind == "edge" and time <= length and count(layers[time]) == 1 and count(layers[time + 1]) == 1)
        if forced then fixed = fixed + 1 end
    end
    return fixed == 2 and "cardinal" or fixed == 1 and "semi_cardinal" or "non_cardinal"
end

local function independent_plan(grid, agents, distances, horizon)
    local paths, restrictions, budget = {}, Low.restrictions(), Low.budget()
    for index, agent in ipairs(agents) do
        paths[index] = Low.search(grid, agent, distances[index], agent.start, 0, restrictions, horizon, budget, false)
    end
    return paths
end

local function conflict_groups(conflicts, n)
    local adjacency, seen, groups = {}, {}, {}
    for i = 1, n do adjacency[i] = {} end
    for _, conflict in ipairs(conflicts) do adjacency[conflict.a][conflict.b], adjacency[conflict.b][conflict.a] = true, true end
    for start = 1, n do
        if not seen[start] and next(adjacency[start]) then
            local queue, head, component = {start}, 1, {}
            seen[start] = true
            while head <= #queue do
                local current = queue[head]
                head = head + 1
                append(component, current)
                for other = 1, n do
                    if adjacency[current][other] and not seen[other] then seen[other] = true; append(queue, other) end
                end
            end
            table.sort(component)
            local names = {}
            for _, index in ipairs(component) do append(names, Report.agent(index)) end
            append(groups, table.concat(names))
        end
    end
    return groups
end

local function instance_overview(grid, agents, distances, independent)
    local overview = {degrees = Grid.statistics(grid), agents = {}, soc_lower = 0, makespan_lower = 0,
        independent_conflicts = CBS.conflicts(independent), classes = {cardinal = 0, semi_cardinal = 0, non_cardinal = 0},
        kinds = {vertex = 0, edge = 0}}
    local restrictions, cache = {}, {}
    for i, agent in ipairs(agents) do
        restrictions[i] = Low.restrictions()
        local shortest = distances[i][agent.start]
        local states, width = mdd_properties(mdd_layers(grid, agent, distances[i], shortest, restrictions[i]))
        overview.agents[i] = {shortest = shortest, mdd_states = states, mdd_width = width}
        overview.soc_lower, overview.makespan_lower = overview.soc_lower + shortest, math.max(overview.makespan_lower, shortest)
    end
    for _, conflict in ipairs(overview.independent_conflicts) do
        conflict.class = conflict_class(conflict, independent, restrictions, grid, agents, distances, cache)
        overview.classes[conflict.class] = overview.classes[conflict.class] + 1
        overview.kinds[conflict.kind] = overview.kinds[conflict.kind] + 1
    end
    overview.groups = conflict_groups(overview.independent_conflicts, #agents)
    return overview
end

local function solve_pp(run, grid, agents, distances, settings)
    for order_number, order in ipairs(settings.orders) do
        run.high_level = run.high_level + 1
        local beginning = run.budget.expansions
        local paths, attempts, failure = Prioritized.try_order(grid, agents, distances, settings.horizon, order, run.budget)
        local names = {}
        for _, index in ipairs(order) do append(names, Report.agent(index)) end
        for _, item in ipairs(attempts) do
            local prefix = string.format("order %d agent %s", order_number, Report.agent(item.agent))
            append(run.trace, prefix .. (item.path and " cost " .. (#item.path - 1) or " failed") .. " expansions " .. item.expansions)
        end
        if failure == "ll_budget" then run.reason = failure; break end
        local summary = string.format("order %d %s planned %d expansions %d", order_number,
            table.concat(names), #attempts - (failure and 1 or 0), run.budget.expansions - beginning)
        if not failure then
            append(run.specific, summary .. " ok")
            run.paths, run.status, run.answer_order = paths, "OK", order_number
            break
        end
        append(run.specific, summary .. " failed " .. Report.agent(failure))
    end
    if run.status == "OK" then run.ending = "end OK order " .. run.answer_order
    else run.reason = run.reason or "orders"; run.ending = "end FAIL " .. run.reason end
end

local function apply_constraint(base, addition)
    local result, index = copy(base), addition.agent
    local changed = result[index]:copy()
    if addition.kind == "vertex" then changed:add_state(addition.source, addition.time)
    else changed:add_move(addition.source, addition.destination, addition.time) end
    result[index] = changed
    return result
end

local function choose_split(node, run, grid, agents, distances)
    if run.solver == "CBS" then return node.conflicts[1], nil end
    local order, cache, best, category, rank = {cardinal = 1, semi_cardinal = 2, non_cardinal = 3}, {}, nil, nil, 4
    for _, conflict in ipairs(node.conflicts) do
        local class = conflict_class(conflict, node.paths, node.constraints, grid, agents, distances, cache)
        if order[class] < rank then best, category, rank = conflict, class, order[class] end
    end
    return best, category
end

local function solve_cbs(run, grid, agents, distances, settings)
    local empty, paths = {}, {}
    for i = 1, #agents do empty[i] = Low.restrictions() end
    for i, agent in ipairs(agents) do
        local path, _, aborted = Low.search(grid, agent, distances[i], agent.start, 0, empty[i], settings.horizon, run.budget, false)
        if aborted then
            run.reason, run.generated, run.ending = "ll_budget", 0, "end FAIL ll_budget"
            append(run.specific, "search expanded 0 generated 0 pruned 0 open 0")
            if run.solver == "ICBS" then append(run.specific, "classes cardinal 0 semi_cardinal 0 non_cardinal 0") end
            return
        end
        paths[i] = path
    end
    local open = Low.heap(CBS.less)
    open:push(CBS.node(paths, empty, 0, 0, nil, run.cost_function))
    local generated, expanded, pruned, reason, answer = 1, 0, 0, "exhausted", nil
    local classes = {cardinal = 0, semi_cardinal = 0, non_cardinal = 0}
    while #open.items > 0 do
        local node = open:pop()
        if #node.conflicts == 0 then answer, reason = node, nil; break end
        if expanded == settings.hl_budget then reason = "hl_budget"; break end
        expanded = expanded + 1
        local conflict, category = choose_split(node, run, grid, agents, distances)
        if category then classes[category] = classes[category] + 1 end
        local created, aborted = {}, false
        for _, branch in ipairs(CBS.split(conflict)) do
            local i, restrictions = branch.agent, apply_constraint(node.constraints, branch)
            local path, _, abort = Low.search(grid, agents[i], distances[i], agents[i].start, 0,
                restrictions[i], settings.horizon, run.budget, false)
            if abort then aborted = true; break end
            if not path then pruned = pruned + 1; append(created, "-")
            else
                local new_paths = copy(node.paths)
                new_paths[i] = path
                open:push(CBS.node(new_paths, restrictions, generated, node.depth + 1, node.number, run.cost_function))
                append(created, tostring(generated))
                generated = generated + 1
            end
        end
        if aborted then reason = "ll_budget"; break end
        local text = string.format("expand %d node %d parent %s depth %d cost %d conflicts %d split %s", expanded,
            node.number, node.parent and tostring(node.parent) or "-", node.depth, node.cost, #node.conflicts, Report.conflict(conflict))
        if category then text = text .. " class " .. category end
        append(run.trace, text .. " children " .. created[1] .. " " .. created[2])
    end
    run.high_level, run.generated = expanded, generated
    append(run.specific, string.format("search expanded %d generated %d pruned %d open %d", expanded, generated, pruned, #open.items))
    if run.solver == "ICBS" then append(run.specific, string.format("classes cardinal %d semi_cardinal %d non_cardinal %d",
        classes.cardinal, classes.semi_cardinal, classes.non_cardinal)) end
    if not answer then run.reason, run.ending = reason, "end FAIL " .. reason; return end
    run.status, run.paths = "OK", answer.paths
    append(run.specific, string.format("solution node %d depth %d", answer.number, answer.depth))
    for _, item in ipairs(CBS.ordered_constraints(answer)) do
        local text = "constraint " .. Report.agent(item.agent)
        if item.kind == 0 then text = text .. " vertex " .. Report.cell(item.source)
        else text = text .. " edge " .. Report.cell(item.source) .. " " .. Report.cell(item.destination) end
        append(run.specific, text .. " t " .. item.time)
    end
    run.ending = string.format("end OK node %d cost %d", answer.number, answer.cost)
end

local function solve_whca(run, grid, agents, distances, settings)
    local current, executed, time, rounds, reason = {}, {}, 0, 0, nil
    for i, agent in ipairs(agents) do current[i], executed[i] = agent.start, {agent.start} end
    while true do
        local finished = true
        for i, agent in ipairs(agents) do if current[i] ~= agent.goal then finished = false end end
        if finished then break end
        if time >= settings.horizon then reason = "timeout"; break end
        rounds = rounds + 1
        local restrictions, order, plans = Low.restrictions(), {}, {}
        for i, agent in ipairs(agents) do if current[i] ~= agent.goal then append(order, i) end end
        for i, agent in ipairs(agents) do if current[i] == agent.goal then append(order, i) end end
        for _, i in ipairs(order) do
            local path, expansions, aborted = Low.search(grid, agents[i], distances[i], current[i], time,
                restrictions, time + settings.window, run.budget, true)
            if aborted then reason = "ll_budget"; break end
            local prefix = string.format("round %d time %d agent %s", rounds, time, Report.agent(i))
            if not path then
                append(run.trace, prefix .. " blocked expansions " .. expansions)
                reason = "blocked"
                break
            end
            while #path < settings.window + 1 do append(path, path[#path]) end
            plans[i] = path
            append(run.trace, prefix .. " moves " .. Report.actions(path) .. " expansions " .. expansions)
            Low.reserve(restrictions, path, time, false)
        end
        if reason then break end
        for i = 1, #agents do
            for k = 2, settings.step + 1 do append(executed[i], plans[i][k]) end
            current[i] = plans[i][settings.step + 1]
        end
        time = time + settings.step
    end
    run.high_level = rounds
    append(run.specific, string.format("window %d step %d rounds %d", settings.window, settings.step, rounds))
    if reason then run.reason, run.ending = reason, "end FAIL " .. reason
    else
        run.status, run.paths, run.ending = "OK", executed, "end OK rounds " .. rounds
        for i, path in ipairs(executed) do
            while #path > 1 and path[#path] == agents[i].goal and path[#path - 1] == agents[i].goal do table.remove(path) end
        end
    end
end

local function run_solvers(grid, agents, distances, settings)
    local results = {}
    for index, definition in ipairs(settings.runs) do
        local run = {name = definition.name, solver = definition.solver, cost_function = definition.cost_function,
            status = "FAIL", high_level = 0, budget = Low.budget(settings.ll_budget), specific = {}, trace = {}, index = index}
        if run.solver == "PP" then solve_pp(run, grid, agents, distances, settings)
        elseif run.solver == "CBS" or run.solver == "ICBS" then solve_cbs(run, grid, agents, distances, settings)
        else solve_whca(run, grid, agents, distances, settings) end
        append(results, run)
    end
    return results
end

local function validate_plan(paths, agents, grid)
    local result = {start = 0, goal = 0, moves = 0, vertex = 0, edge = 0, follows = 0, conflicts = CBS.conflicts(paths)}
    local horizon = 0
    for i, path in ipairs(paths) do
        if path[1] ~= agents[i].start then result.start = result.start + 1 end
        if path[#path] ~= agents[i].goal then result.goal = result.goal + 1 end
        horizon = math.max(horizon, #path - 1)
        for step = 2, #path do
            local allowed = false
            for _, destination in ipairs(grid.destinations[path[step - 1]] or {}) do
                if destination == path[step] then allowed = true; break end
            end
            if not allowed then result.moves = result.moves + 1 end
        end
    end
    for _, conflict in ipairs(result.conflicts) do result[conflict.kind] = result[conflict.kind] + 1 end
    for time = 1, horizon do
        for a = 1, #paths do
            local past_a, next_a = CBS.position(paths[a], time - 1), CBS.position(paths[a], time)
            if next_a ~= past_a then
                for b = 1, #paths do
                    if a ~= b and next_a == CBS.position(paths[b], time - 1) and CBS.position(paths[b], time) ~= past_a then
                        result.follows = result.follows + 1
                    end
                end
            end
        end
    end
    result.verdict = result.start + result.goal + result.moves + result.vertex + result.edge == 0 and "VALID" or "INVALID"
    return result
end

local function path_statistics(path, goal, lower)
    local result = {cost = #path - 1, extra = #path - 1 - lower, waits = 0, turns = 0, leave = 0, actions = Report.actions(path)}
    local previous
    for time = 0, #path - 1 do
        if path[time + 1] == goal and result.arrive == nil then result.arrive = time end
        if time > 0 then
            local action = result.actions:sub(time, time)
            if action == "." then result.waits = result.waits + 1
            else
                if previous and previous ~= action then result.turns = result.turns + 1 end
                previous = action
            end
            if path[time] == goal and path[time + 1] ~= goal then result.leave = result.leave + 1 end
        end
    end
    return result
end

local function plan_statistics(paths, agents, overview, cost_function)
    local result = {soc = 0, makespan = 0, agents = {}, sum_extra = 0, max_extra = 0,
        waits = 0, turns = 0, arrivals = {}, traffic = {}, cell_waits = {}, hotspots = {}}
    for i, path in ipairs(paths) do
        local record = path_statistics(path, agents[i].goal, overview.agents[i].shortest)
        result.agents[i] = record
        result.soc, result.makespan = result.soc + record.cost, math.max(result.makespan, record.cost)
        result.sum_extra, result.max_extra = result.sum_extra + record.extra, math.max(result.max_extra, record.extra)
        result.waits, result.turns = result.waits + record.waits, result.turns + record.turns
        local visited = {}
        for step, cell in ipairs(path) do
            if not visited[cell] then result.traffic[cell] = (result.traffic[cell] or 0) + 1; visited[cell] = true end
            if step > 1 and cell == path[step - 1] then result.cell_waits[cell] = (result.cell_waits[cell] or 0) + 1 end
        end
    end
    result.cost = cost_function == "SOC" and result.soc or result.makespan
    result.ratio = Report.fraction(result.cost, cost_function == "SOC" and overview.soc_lower or overview.makespan_lower)
    for time = 0, result.makespan do
        local n = 0
        for _, path in ipairs(paths) do if #path - 1 <= time then n = n + 1 end end
        append(result.arrivals, n)
    end
    for cell in pairs(result.traffic) do append(result.hotspots, cell) end
    table.sort(result.hotspots, function(a, b)
        if result.traffic[a] ~= result.traffic[b] then return result.traffic[a] > result.traffic[b] end
        return a < b
    end)
    while #result.hotspots > 5 do table.remove(result.hotspots) end
    return result
end

local function delayed_execution(paths, settings)
    local steps, prerequisites, progress, finish = {}, {}, {}, {}
    for i, path in ipairs(paths) do
        local entries = {{time = 0, cell = path[1]}}
        for time = 1, #path - 1 do
            if path[time + 1] ~= path[time] then append(entries, {time = time, cell = path[time + 1]}) end
        end
        steps[i], progress[i] = entries, 1
        if #entries == 1 then finish[i] = 0 end
    end
    for i, entries in ipairs(steps) do
        prerequisites[i] = {}
        for index = 2, #entries do
            local requests = {}
            for j, others in ipairs(steps) do
                if j ~= i then
                    for k, other in ipairs(others) do
                        if other.cell == entries[index].cell and other.time < entries[index].time then append(requests, {j, k}) end
                    end
                end
            end
            prerequisites[i][index] = requests
        end
    end
    local holds, time = 0, 0
    while true do
        local unfinished = false
        for i = 1, #paths do if progress[i] < #steps[i] then unfinished = true end end
        if not unfinished then break end
        local advances, stopped_count = {}, 0
        for i = 1, #paths do
            if progress[i] < #steps[i] then
                local stopped = false
                for _, delay in ipairs(settings.delays) do
                    if delay.agent == i and delay.start <= time and time < delay.start + delay.duration then stopped = true; break end
                end
                if stopped then stopped_count = stopped_count + 1
                else
                    local allowed = true
                    for _, request in ipairs(prerequisites[i][progress[i] + 1]) do
                        if progress[request[1]] <= request[2] then allowed = false; break end
                    end
                    if allowed then append(advances, i) else holds = holds + 1 end
                end
            end
        end
        if #advances == 0 and stopped_count == 0 then return {deadlock = time, blocked = holds} end
        for _, i in ipairs(advances) do
            progress[i] = progress[i] + 1
            if progress[i] == #steps[i] then finish[i] = time + 1 end
        end
        time = time + 1
    end
    local soc, makespan = 0, 0
    for _, value in ipairs(finish) do soc, makespan = soc + value, math.max(makespan, value) end
    return {blocked = holds, finish = finish, soc = soc, makespan = makespan}
end

local function complete_runs(results, agents, grid, overview, settings)
    for _, run in ipairs(results) do
        if run.status == "OK" then
            run.metrics = plan_statistics(run.paths, agents, overview, run.cost_function)
            run.validation = validate_plan(run.paths, agents, grid)
            run.execution = delayed_execution(run.paths, settings)
        end
    end
end

local function instance_lines(grid, agents, overview)
    local degree = overview.degrees
    local result = {string.format("instance width %d height %d free %d agents %d", grid.width, grid.height, #grid.cells, #agents),
        string.format("map isolated %d dead_ends %d corridors %d junctions %d components %d", degree.isolated,
            degree.dead_ends, degree.corridors, degree.junctions, degree.components)}
    for i, agent in ipairs(agents) do
        local record = overview.agents[i]
        append(result, string.format("agent %s start %s goal %s distance %d mdd %d width %d", agent.name,
            Report.cell(agent.start), Report.cell(agent.goal), record.shortest, record.mdd_states, record.mdd_width))
    end
    append(result, string.format("lower_bound soc %d makespan %d", overview.soc_lower, overview.makespan_lower))
    append(result, string.format("independent conflicts %d vertex %d edge %d cardinal %d semi_cardinal %d non_cardinal %d",
        #overview.independent_conflicts, overview.kinds.vertex, overview.kinds.edge, overview.classes.cardinal,
        overview.classes.semi_cardinal, overview.classes.non_cardinal))
    append(result, "groups " .. (#overview.groups == 0 and "-" or table.concat(overview.groups, " ")))
    return result
end

local function successful_run_lines(run, agents)
    local metrics, execution = run.metrics, run.execution
    local result = {string.format("run %s solver %s cost_function %s result OK cost %d soc %d makespan %d ratio %s",
        run.name, run.solver, run.cost_function, metrics.cost, metrics.soc, metrics.makespan, metrics.ratio)}
    extend(result, run.specific)
    for i, agent in ipairs(agents) do
        local record = metrics.agents[i]
        append(result, string.format("agent %s cost %d extra %d waits %d turns %d arrive %d leave %d moves %s",
            agent.name, record.cost, record.extra, record.waits, record.turns, record.arrive, record.leave, record.actions))
    end
    append(result, "arrivals " .. table.concat(metrics.arrivals, " "))
    local hotspots = {}
    for _, cell in ipairs(metrics.hotspots) do append(hotspots, Report.cell(cell) .. ":" .. metrics.traffic[cell]) end
    append(result, "hotspots " .. table.concat(hotspots, " "))
    if execution.deadlock ~= nil then append(result, "execution deadlock time " .. execution.deadlock)
    else append(result, string.format("execution soc %d makespan %d blocked %d finish %s", execution.soc,
        execution.makespan, execution.blocked, table.concat(execution.finish, " "))) end
    return result
end

local function solution_lines(grid, agents, overview, results)
    local lines, succeeded = instance_lines(grid, agents, overview), {}
    for _, run in ipairs(results) do
        append(lines, "")
        if run.status == "OK" then extend(lines, successful_run_lines(run, agents)); append(succeeded, run)
        else
            append(lines, string.format("run %s solver %s cost_function %s result FAIL reason %s",
                run.name, run.solver, run.cost_function, run.reason))
            extend(lines, run.specific)
        end
    end
    append(lines, "")
    append(lines, string.format("summary ok %d failed %d", #succeeded, #results - #succeeded))
    if #succeeded > 0 then
        local best_soc, best_span = math.maxinteger, math.maxinteger
        for _, run in ipairs(succeeded) do best_soc, best_span = math.min(best_soc, run.metrics.soc), math.min(best_span, run.metrics.makespan) end
        local soc_names, span_names = {}, {}
        for _, run in ipairs(succeeded) do
            if run.metrics.soc == best_soc then append(soc_names, run.name) end
            if run.metrics.makespan == best_span then append(span_names, run.name) end
        end
        append(lines, "best_soc " .. best_soc .. " " .. table.concat(soc_names, " "))
        append(lines, "best_makespan " .. best_span .. " " .. table.concat(span_names, " "))
        table.sort(succeeded, function(a, b)
            if a.metrics.soc ~= b.metrics.soc then return a.metrics.soc < b.metrics.soc end
            if a.metrics.makespan ~= b.metrics.makespan then return a.metrics.makespan < b.metrics.makespan end
            return a.index < b.index
        end)
        local ranking = {}
        for _, run in ipairs(succeeded) do append(ranking, run.name) end
        append(lines, "ranking " .. table.concat(ranking, " "))
    end
    return lines
end

local function stats_lines(results)
    local lines = {"run,solver,cost_function,result,reason,cost,soc,makespan,sum_extra,max_extra,waits,turns,exec_soc,exec_makespan,high_level,generated,searches,expansions"}
    for _, run in ipairs(results) do
        local fields = {run.name, run.solver, run.cost_function, run.status, run.reason or "-"}
        if run.status == "OK" then
            local m, e = run.metrics, run.execution
            extend(fields, {m.cost, m.soc, m.makespan, m.sum_extra, m.max_extra, m.waits, m.turns})
            if e.deadlock == nil then extend(fields, {e.soc, e.makespan}) else extend(fields, {"-", "-"}) end
        else for _ = 1, 9 do append(fields, "-") end end
        extend(fields, {run.high_level, run.generated or "-", run.budget.searches, run.budget.expansions})
        append(lines, Report.csv(fields))
    end
    return lines
end

local function validation_lines(results, independent, agents, grid, overview)
    local baseline = validate_plan(independent, agents, grid)
    baseline.conflicts = overview.independent_conflicts
    local plans = {{name = "INDEPENDENT", validation = baseline}}
    extend(plans, results)
    local lines = {}
    for _, plan in ipairs(plans) do
        local v = plan.validation
        if not v then append(lines, "plan " .. plan.name .. " verdict NONE")
        else
            append(lines, string.format("plan %s verdict %s start %d goal %d moves %d vertex %d edge %d follows %d",
                plan.name, v.verdict, v.start, v.goal, v.moves, v.vertex, v.edge, v.follows))
            for _, conflict in ipairs(v.conflicts) do
                append(lines, "  " .. Report.conflict(conflict) .. (plan.name == "INDEPENDENT" and " " .. conflict.class or ""))
            end
        end
    end
    return lines
end

local function trace_lines(results)
    local lines = {}
    for index, run in ipairs(results) do
        if index > 1 then append(lines, "") end
        append(lines, "run " .. run.name)
        extend(lines, run.trace)
        append(lines, run.ending)
    end
    return lines
end

local function count_picture(grid, counts)
    local glyphs = {}
    for cell, value in pairs(counts) do
        if value > 0 then glyphs[cell] = value <= 9 and tostring(value) or "+" end
    end
    return Report.picture(grid, glyphs)
end

local function animation_lines(results, grid, agents, settings)
    local selected
    for _, run in ipairs(results) do if run.name == settings.animate then selected = run; break end end
    if selected.status ~= "OK" then return {"run " .. selected.name .. " FAIL"} end
    local paths, metrics = selected.paths, selected.metrics
    local lines = {string.format("run %s frames %d", selected.name, settings.frames)}
    for time = 0, settings.frames - 1 do
        local done, moving, waiting, glyphs = 0, 0, 0, {}
        for _, agent in ipairs(agents) do glyphs[agent.goal] = agent.name:lower() end
        for i, path in ipairs(paths) do
            if time >= #path - 1 then done = done + 1
            elseif time >= 1 and CBS.position(path, time) ~= CBS.position(path, time - 1) then moving = moving + 1
            else waiting = waiting + 1 end
            glyphs[CBS.position(path, time)] = agents[i].name
        end
        append(lines, "")
        append(lines, string.format("frame %d done %d moving %d waiting %d", time, done, moving, waiting))
        extend(lines, Report.picture(grid, glyphs))
    end
    append(lines, "")
    append(lines, "traffic")
    extend(lines, count_picture(grid, metrics.traffic))
    append(lines, "")
    append(lines, "waits")
    extend(lines, count_picture(grid, metrics.cell_waits))
    return lines
end

local grid = Grid.read()
local agents = Grid.agents()
local settings, distances = parameters(#agents), {}
for i, agent in ipairs(agents) do distances[i] = Grid.distance(grid, agent.goal) end
local independent = independent_plan(grid, agents, distances, settings.horizon)
local overview = instance_overview(grid, agents, distances, independent)
local results = run_solvers(grid, agents, distances, settings)
complete_runs(results, agents, grid, overview, settings)
assert(os.execute("mkdir -p output"))
Report.save("solutions.txt", solution_lines(grid, agents, overview, results))
Report.save("stats.csv", stats_lines(results))
Report.save("validation.txt", validation_lines(results, independent, agents, grid, overview))
Report.save("trace.txt", trace_lines(results))
Report.save("frames.txt", animation_lines(results, grid, agents, settings))
