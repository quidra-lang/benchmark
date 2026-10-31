local Sets = require("grounding")
local Graph = {}
Graph.__index = Graph

local function pair(first, second)
    return math.min(first, second) .. ":" .. math.max(first, second)
end

local function compatible(facts, mutexes)
    local ordered = Sets.sorted(facts)
    for i, first in ipairs(ordered) do
        for j = i + 1, #ordered do if mutexes[pair(first, ordered[j])] then return false end end
    end
    return true
end

local function conflict(first, second, mutexes)
    if Sets.intersects(first.delete, Sets.union(second.pre, second.add))
        or Sets.intersects(second.delete, Sets.union(first.pre, first.add)) then return true end
    for p in pairs(first.pre) do for q in pairs(second.pre) do if mutexes[pair(p, q)] then return true end end end
    return false
end

function Graph.new(actions, initial, goal, limit)
    return setmetatable({actions = actions, goal = goal, limit = limit, facts = {initial}, fact_mutexes = {{}},
        elements = {}, element_mutexes = {}, achievers = {}, memo = {}, lines = {}, searched = 0, memo_hits = 0, tried = 0}, Graph)
end

function Graph:expand(level)
    local facts, mutexes, elements = self.facts[level + 1], self.fact_mutexes[level + 1], {}
    for _, action in ipairs(self.actions) do
        if Sets.subset(action.pre, facts) and compatible(action.pre, mutexes) then elements[#elements + 1] = action end
    end
    local action_count = #elements
    for _, fact in ipairs(Sets.sorted(facts)) do elements[#elements + 1] = {pre = {[fact] = true}, add = {[fact] = true}, delete = {}} end
    local exclusive = {}
    for i, first in ipairs(elements) do
        for j = i + 1, #elements do if conflict(first, elements[j], mutexes) then exclusive[pair(i, j)] = true end end
    end
    self.lines[#self.lines + 1] = string.format("action level %d: actions=%d noops=%d mutexes=%d", level, action_count,
        Sets.size(facts), Sets.size(exclusive))
    local achievers, following, following_mutexes = {}, {}, {}
    for index, element in ipairs(elements) do
        for fact in pairs(element.add) do
            achievers[fact] = achievers[fact] or {}
            local list = achievers[fact]
            list[#list + 1], following[fact] = index, true
        end
    end
    for _, list in pairs(achievers) do
        table.sort(list, function(a, b) return (elements[a].number or 0) < (elements[b].number or 0) end)
    end
    local ordered = Sets.sorted(following)
    for i, first in ipairs(ordered) do
        for j = i + 1, #ordered do
            local second, all_exclusive = ordered[j], true
            for _, x in ipairs(achievers[first]) do
                for _, y in ipairs(achievers[second]) do
                    if x == y or not exclusive[pair(x, y)] then all_exclusive = false; break end
                end
                if not all_exclusive then break end
            end
            if all_exclusive then following_mutexes[pair(first, second)] = true end
        end
    end
    self.elements[level + 1], self.element_mutexes[level + 1], self.achievers[level + 1] = elements, exclusive, achievers
    self.facts[level + 2], self.fact_mutexes[level + 2] = following, following_mutexes
end

function Graph:extract(level, goals)
    if level == 0 then return {} end
    local key = level .. ":" .. table.concat(goals, ",")
    if self.memo[key] then self.memo_hits = self.memo_hits + 1; return nil end
    self.searched = self.searched + 1
    local layers = self:assign(level, goals, 1, {})
    if not layers then self.memo[key] = true end
    return layers
end

function Graph:assign(level, goals, position, chosen)
    local elements = self.elements[level]
    while position <= #goals do
        local covered = false
        for _, index in ipairs(chosen) do if elements[index].add[goals[position]] then covered = true; break end end
        if not covered then break end
        position = position + 1
    end
    if position > #goals then
        local previous, layer = {}, {}
        for _, index in ipairs(chosen) do
            local element = elements[index]
            for fact in pairs(element.pre) do previous[fact] = true end
            if element.number then layer[#layer + 1] = element.number end
        end
        local layers = self:extract(level - 1, Sets.sorted(previous))
        if not layers then return nil end
        table.sort(layer)
        layers[#layers + 1] = layer
        return layers
    end
    for _, index in ipairs(self.achievers[level][goals[position]]) do
        local allowed = true
        for _, other in ipairs(chosen) do if self.element_mutexes[level][pair(index, other)] then allowed = false; break end end
        if allowed then
            self.tried = self.tried + 1
            chosen[#chosen + 1] = index
            local layers = self:assign(level, goals, position + 1, chosen)
            chosen[#chosen] = nil
            if layers then return layers end
        end
    end
end

function Graph:finish(status, layers)
    layers = layers or {}
    local plan = {}
    for _, layer in ipairs(layers) do for _, number in ipairs(layer) do plan[#plan + 1] = number end end
    return {status = status, plan = plan, layers = layers, lines = self.lines, expanded = self.searched,
        generated = self.tried, memo_hits = self.memo_hits}
end

function Graph:run()
    for level = 0, self.limit do
        local facts, mutexes = self.facts[level + 1], self.fact_mutexes[level + 1]
        self.lines[#self.lines + 1] = string.format("fact level %d: facts=%d mutexes=%d", level, Sets.size(facts), Sets.size(mutexes))
        local possible = Sets.subset(self.goal, facts) and compatible(self.goal, mutexes)
        if possible then
            local searched, hits = self.searched, self.memo_hits
            local layers = self:extract(level, Sets.sorted(self.goal))
            self.lines[#self.lines + 1] = string.format("extract level %d: %s searched=%d memo_hits=%d", level,
                layers and "success" or "fail", self.searched - searched, self.memo_hits - hits)
            if layers then return self:finish("solved", layers) end
        elseif level >= 1 and Sets.size(facts) == Sets.size(self.facts[level]) and Sets.size(mutexes) == Sets.size(self.fact_mutexes[level]) then
            return self:finish("unreachable")
        end
        if level == self.limit then return self:finish("level limit") end
        self:expand(level)
    end
end

return Graph
