local Sets = require("grounding")
local Search = require("search")
local Heuristics = {}
Heuristics.__index = Heuristics
Heuristics.INF = math.maxinteger
Heuristics.names = {"goalcount", "hmax", "hadd", "ff", "lmcount"}

function Heuristics.new(problem)
    local self = setmetatable({actions = problem.actions, goal = problem.goal, fact_count = #problem.facts,
        achievers = {}, consumers = {}, cache = {}}, Heuristics)
    for i = 1, #problem.facts do self.achievers[i], self.consumers[i] = {}, {} end
    for _, action in ipairs(problem.actions) do
        for fact in pairs(action.add) do local list = self.achievers[fact]; list[#list + 1] = action.number end
        for fact in pairs(action.pre) do local list = self.consumers[fact]; list[#list + 1] = action.number end
    end
    return self
end

function Heuristics:entry(state)
    local key = Sets.key(state)
    if not self.cache[key] then self.cache[key] = {} end
    return self.cache[key]
end

function Heuristics:relaxed_costs(state, maximum)
    local entry, name = self:entry(state), maximum and "maximum" or "additive"
    if entry[name] then return entry[name] end
    local costs = {}
    for i = 1, self.fact_count do costs[i] = state[i] and 0 or self.INF end
    while true do
        local changed = false
        for _, action in ipairs(self.actions) do
            local aggregate, finite = 0, true
            for fact in pairs(action.pre) do
                if costs[fact] == self.INF then finite = false; break end
                aggregate = maximum and math.max(aggregate, costs[fact]) or aggregate + costs[fact]
            end
            if finite then
                local value = action.cost + aggregate
                for fact in pairs(action.add) do if value < costs[fact] then costs[fact], changed = value, true end end
            end
        end
        if not changed then break end
    end
    entry[name] = costs
    return costs
end

function Heuristics:relaxed_plan(state)
    local entry = self:entry(state)
    if entry.plan ~= nil then return entry.plan end
    local costs = self:relaxed_costs(state, false)
    for fact in pairs(self.goal) do if costs[fact] == self.INF then entry.plan = false; return false end end
    local chosen, pending = {}, Sets.sorted(Sets.difference(self.goal, state))
    while #pending > 0 do
        local fact = table.remove(pending)
        local winner, lowest = nil, self.INF
        for _, number in ipairs(self.achievers[fact]) do
            local action, cost, finite = self.actions[number], self.actions[number].cost, true
            for pre in pairs(action.pre) do if costs[pre] == self.INF then finite = false; break end; cost = cost + costs[pre] end
            if finite and cost < lowest then winner, lowest = number, cost end
        end
        if not chosen[winner] then
            chosen[winner] = true
            for pre in pairs(self.actions[winner].pre) do if not state[pre] then pending[#pending + 1] = pre end end
        end
    end
    entry.plan = Sets.sorted(chosen)
    return entry.plan
end

function Heuristics:helpful(state)
    local entry = self:entry(state)
    if entry.helpful then return entry.helpful end
    local result = {}
    for _, number in ipairs(self:relaxed_plan(state) or {}) do
        if Search.applicable(self.actions[number], state) then result[#result + 1] = number end
    end
    entry.helpful = result
    return result
end

function Heuristics:levels(state)
    local entry = self:entry(state)
    if entry.fact_levels then return entry.fact_levels, entry.action_levels end
    local facts, actions, level = {}, {}, 0
    for i = 1, self.fact_count do facts[i] = state[i] and 0 or self.INF end
    for i = 1, #self.actions do actions[i] = self.INF end
    while true do
        local changed = false
        for _, action in ipairs(self.actions) do
            if actions[action.number] == self.INF then
                local enabled = true
                for fact in pairs(action.pre) do if facts[fact] > level then enabled = false; break end end
                if enabled then
                    actions[action.number] = level
                    for fact in pairs(action.add) do if facts[fact] == self.INF then facts[fact], changed = level + 1, true end end
                end
            end
        end
        if not changed then break end
        level = level + 1
    end
    entry.fact_levels, entry.action_levels = facts, actions
    return facts, actions
end

function Heuristics:verified(state, excluded_fact)
    local excluded, reachable = {}, Sets.copy(state)
    for _, number in ipairs(self.achievers[excluded_fact]) do excluded[number] = true end
    while true do
        local changed = false
        for _, action in ipairs(self.actions) do
            if not excluded[action.number] and Sets.subset(action.pre, reachable) then
                for fact in pairs(action.add) do if not reachable[fact] then reachable[fact], changed = true, true end end
            end
        end
        if not changed then break end
    end
    return not Sets.subset(self.goal, reachable)
end

function Heuristics:landmarks(state)
    local entry = self:entry(state)
    if entry.landmarks ~= nil then return entry.landmarks end
    local facts, actions = self:levels(state)
    for fact in pairs(self.goal) do if facts[fact] == self.INF then entry.landmarks = false; return false end end
    local landmarks = Sets.difference(self.goal, state)
    local pending, head, verification = Sets.sorted(landmarks), 1, {}
    while head <= #pending do
        local fact, candidates = pending[head], nil
        head = head + 1
        for _, number in ipairs(self.achievers[fact]) do
            if actions[number] == facts[fact] - 1 then
                candidates = candidates and Sets.intersection(candidates, self.actions[number].pre) or Sets.copy(self.actions[number].pre)
            end
        end
        for _, candidate in ipairs(Sets.sorted(Sets.difference(Sets.difference(candidates, state), landmarks))) do
            if verification[candidate] == nil then verification[candidate] = self:verified(state, candidate) end
            if verification[candidate] then landmarks[candidate] = true; pending[#pending + 1] = candidate end
        end
    end
    entry.landmarks = landmarks
    return landmarks
end

function Heuristics:value(name, state)
    if name == "none" then return 0 end
    if name == "goalcount" then return Sets.size(Sets.difference(self.goal, state)) end
    if name == "hmax" or name == "hadd" then
        local costs, result = self:relaxed_costs(state, name == "hmax"), 0
        for fact in pairs(self.goal) do
            if costs[fact] == self.INF then return self.INF end
            result = name == "hmax" and math.max(result, costs[fact]) or result + costs[fact]
        end
        return result
    end
    if name == "ff" then
        local plan = self:relaxed_plan(state)
        if not plan then return self.INF end
        local cost = 0
        for _, number in ipairs(plan) do cost = cost + self.actions[number].cost end
        return cost
    end
    local landmarks = self:landmarks(state)
    return landmarks and Sets.size(landmarks) or self.INF
end

function Heuristics:values(state)
    local result = {}
    for _, name in ipairs(self.names) do result[name] = self:value(name, state) end
    return result
end

return Heuristics
