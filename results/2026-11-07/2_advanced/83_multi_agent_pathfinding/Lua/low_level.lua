local Grid = require("grid_map")
local Low = {}
local Restrictions = {}
Restrictions.__index = Restrictions

function Low.restrictions()
    return setmetatable({states = {}, moves = {}, permanent = {}}, Restrictions)
end

local function state_key(cell, time)
    return time * Grid.area + cell
end

local function move_key(source, destination, time)
    return (time * Grid.area + source) * Grid.area + destination
end

function Restrictions:add_state(cell, time)
    self.states[state_key(cell, time)] = {cell = cell, time = time}
end

function Restrictions:add_move(source, destination, time)
    self.moves[move_key(source, destination, time)] = {source = source, destination = destination, time = time}
end

function Restrictions:copy()
    local result = Low.restrictions()
    for _, name in ipairs({"states", "moves", "permanent"}) do
        for key, value in pairs(self[name]) do result[name][key] = value end
    end
    return result
end

function Restrictions:allowed(source, destination, time)
    if self.states[state_key(destination, time)] then return false end
    local permanent = self.permanent[destination]
    if permanent and permanent <= time then return false end
    return source == destination or not self.moves[move_key(source, destination, time)]
end

function Restrictions:arrival(goal)
    local arrival = 0
    for _, item in pairs(self.states) do
        if item.cell == goal then arrival = math.max(arrival, item.time + 1) end
    end
    return arrival
end

function Low.reserve(restrictions, path, start_time, permanent)
    start_time = start_time or 0
    for index, cell in ipairs(path) do
        local time = start_time + index - 1
        restrictions:add_state(cell, time)
        if index > 1 and cell ~= path[index - 1] then restrictions:add_move(cell, path[index - 1], time) end
    end
    if permanent then
        local goal, time = path[#path], start_time + #path - 1
        restrictions.permanent[goal] = math.min(restrictions.permanent[goal] or time, time)
    end
end

local Heap = {}
Heap.__index = Heap

function Low.heap(less)
    return setmetatable({items = {}, less = less}, Heap)
end

function Heap:push(value)
    local items, index = self.items, #self.items + 1
    while index > 1 do
        local parent = index // 2
        if not self.less(value, items[parent]) then break end
        items[index], index = items[parent], parent
    end
    items[index] = value
end

function Heap:pop()
    local items, result = self.items, self.items[1]
    local last = table.remove(items)
    if #items > 0 then
        local index = 1
        while index * 2 <= #items do
            local child = index * 2
            if child < #items and self.less(items[child + 1], items[child]) then child = child + 1 end
            if not self.less(items[child], last) then break end
            items[index], index = items[child], child
        end
        items[index] = last
    end
    return result
end

function Low.budget(limit)
    return {limit = limit, searches = 0, expansions = 0}
end

function Low.search(grid, agent, distances, start, t0, restrictions, tmax, budget, window)
    budget.searches = budget.searches + 1
    local beginning, insertion, arrival = budget.expansions, 0, restrictions:arrival(agent.goal)
    local heap = Low.heap(function(a, b)
        if a.f ~= b.f then return a.f < b.f end
        if a.g ~= b.g then return a.g > b.g end
        return a.number < b.number
    end)
    heap:push({cell = start, time = t0, f = distances[start], g = 0, number = 0})
    local generated = {[state_key(start, t0)] = true}
    while #heap.items > 0 do
        local state = heap:pop()
        budget.expansions = budget.expansions + 1
        if budget.limit and budget.expansions > budget.limit then return nil, budget.expansions - beginning, true end
        if (state.cell == agent.goal and state.time >= arrival) or (window and state.time == tmax) then
            local reverse, path = {}, {}
            while state do reverse[#reverse + 1] = state.cell; state = state.parent end
            for i = #reverse, 1, -1 do path[#path + 1] = reverse[i] end
            return path, budget.expansions - beginning, false
        end
        if state.time < tmax then
            local time = state.time + 1
            for _, destination in ipairs(grid.destinations[state.cell]) do
                local key = state_key(destination, time)
                if distances[destination] ~= nil and not generated[key] and restrictions:allowed(state.cell, destination, time) then
                    insertion = insertion + 1
                    generated[key] = true
                    local g = time - t0
                    heap:push({cell = destination, time = time, g = g, f = g + distances[destination],
                        number = insertion, parent = state})
                end
            end
        end
    end
    return nil, budget.expansions - beginning, false
end

return Low
