local Sets = require("grounding")
local Search = {}

function Search.applicable(action, state)
    return Sets.subset(action.pre, state) and not Sets.intersects(action.neg, state)
end

function Search.apply(action, state)
    return Sets.union(Sets.difference(state, action.delete), action.add)
end

function Search.result(status, expanded, generated, plan)
    return {status = status, expanded = expanded or 0, generated = generated or 0, plan = plan or {}}
end

local Heap = {}
Heap.__index = Heap

function Search.heap()
    return setmetatable({items = {}}, Heap)
end

local function less(a, b)
    if a.f ~= b.f then return a.f < b.f end
    if a.h ~= b.h then return a.h < b.h end
    return a.serial < b.serial
end

function Heap:push(node)
    local items, i = self.items, #self.items + 1
    while i > 1 do
        local parent = i // 2
        if not less(node, items[parent]) then break end
        items[i], i = items[parent], parent
    end
    items[i] = node
end

function Heap:pop()
    local items, result = self.items, self.items[1]
    local last = table.remove(items)
    if #items > 0 then
        local i = 1
        while i * 2 <= #items do
            local child = i * 2
            if child < #items and less(items[child + 1], items[child]) then child = child + 1 end
            if not less(items[child], last) then break end
            items[i], i = items[child], child
        end
        items[i] = last
    end
    return result
end

local function reconstruct(node)
    local reverse, plan = {}, {}
    while node.parent do reverse[#reverse + 1], node = node.action, node.parent end
    for i = #reverse, 1, -1 do plan[#plan + 1] = reverse[i] end
    return plan
end

local function priority(algorithm, g, depth, h, weight)
    if algorithm == "bfs" then return depth end
    if algorithm == "ucs" then return g end
    if algorithm == "gbfs" then return h end
    return g + h * (algorithm == "wastar" and weight or 1)
end

local function best_first(problem, start, algorithm, heuristic, budget, weight, evaluator)
    local h = evaluator:value(heuristic, start)
    if h == evaluator.INF then return Search.result("dead end") end
    local queue, best = Search.heap(), {[Sets.key(start)] = 0}
    queue:push({state = start, g = 0, depth = 0, f = priority(algorithm, 0, 0, h, weight), h = h, serial = 0})
    local serial, expanded, generated = 1, 0, 0
    local reopen = algorithm == "ucs" or algorithm == "astar" or algorithm == "wastar"
    while #queue.items > 0 do
        local node = queue:pop()
        if not reopen or node.g <= best[Sets.key(node.state)] then
            if Sets.subset(problem.goal, node.state) then return Search.result("solved", expanded, generated, reconstruct(node)) end
            if expanded == budget then return Search.result("budget", expanded, generated) end
            expanded = expanded + 1
            for _, action in ipairs(problem.actions) do
                if Search.applicable(action, node.state) then
                    local state, cost = Search.apply(action, node.state), node.g + action.cost
                    generated = generated + 1
                    local key = Sets.key(state)
                    if best[key] == nil or (reopen and cost < best[key]) then
                        best[key] = cost
                        local value = evaluator:value(heuristic, state)
                        if value ~= evaluator.INF then
                            queue:push({state = state, g = cost, depth = node.depth + 1, parent = node, action = action.number,
                                f = priority(algorithm, cost, node.depth + 1, value, weight), h = value, serial = serial})
                            serial = serial + 1
                        end
                    end
                end
            end
        end
    end
    return Search.result("exhausted", expanded, generated)
end

local function hill_climbing(problem, start, heuristic, budget, evaluator)
    local current, plan, current_h = start, {}, evaluator:value(heuristic, start)
    local expanded, generated = 0, 0
    if current_h == evaluator.INF then return Search.result("dead end") end
    while not Sets.subset(problem.goal, current) do
        local queue, visited, head, improved = {{state = current, prefix = {}}}, {[Sets.key(current)] = true}, 1, false
        while head <= #queue and not improved do
            local entry = queue[head]
            head = head + 1
            if expanded == budget then return Search.result("budget", expanded, generated) end
            expanded = expanded + 1
            for _, number in ipairs(evaluator:helpful(entry.state)) do
                local successor = Search.apply(problem.actions[number], entry.state)
                generated = generated + 1
                local key = Sets.key(successor)
                if not visited[key] then
                    visited[key] = true
                    local value = evaluator:value(heuristic, successor)
                    if value ~= evaluator.INF then
                        local path = Sets.copy(entry.prefix)
                        path[#path + 1] = number
                        if value < current_h then
                            for _, action in ipairs(path) do plan[#plan + 1] = action end
                            current, current_h, improved = successor, value, true
                            break
                        end
                        queue[#queue + 1] = {state = successor, prefix = path}
                    end
                end
            end
        end
        if not improved then return Search.result("stuck", expanded, generated) end
    end
    return Search.result("solved", expanded, generated, plan)
end

function Search.run(problem, start, algorithm, heuristic, budget, weight, evaluator)
    if algorithm == "ehc" then return hill_climbing(problem, start, heuristic, budget, evaluator) end
    return best_first(problem, start, algorithm, heuristic, budget, weight, evaluator)
end

return Search
