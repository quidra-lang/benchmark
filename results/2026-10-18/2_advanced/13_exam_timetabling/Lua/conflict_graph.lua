local Graph = {}
Graph.__index = Graph

local function keys(map)
    local result = {}
    for key in pairs(map) do
        result[#result + 1] = key
    end
    table.sort(result)
    return result
end

function Graph.new(vertices, student_courses)
    local self = setmetatable({vertices = {}, shared = {}}, Graph)
    for _, id in ipairs(vertices) do
        self.vertices[#self.vertices + 1] = id
        self.shared[id] = {}
    end
    table.sort(self.vertices)
    for _, list in pairs(student_courses) do
        for i = 1, #list do
            for j = i + 1, #list do
                local first, second = list[i], list[j]
                self.shared[first][second] = (self.shared[first][second] or 0) + 1
                self.shared[second][first] = (self.shared[second][first] or 0) + 1
            end
        end
    end
    return self
end

function Graph:neighbours(id)
    return self.shared[id] or {}
end

function Graph:degree(id)
    local count = 0
    for _ in pairs(self:neighbours(id)) do
        count = count + 1
    end
    return count
end

function Graph:shared_total(id)
    local total = 0
    for _, count in pairs(self:neighbours(id)) do
        total = total + count
    end
    return total
end

function Graph:edges()
    local result = {}
    for _, first in ipairs(self.vertices) do
        for _, second in ipairs(keys(self.shared[first])) do
            if first < second then
                result[#result + 1] = {first, second, self.shared[first][second]}
            end
        end
    end
    return result
end

function Graph:components()
    local seen, components = {}, {}
    for _, vertex in ipairs(self.vertices) do
        if not seen[vertex] then
            seen[vertex] = true
            local component = {vertex}
            local index = 1
            while index <= #component do
                for neighbour in pairs(self:neighbours(component[index])) do
                    if not seen[neighbour] then
                        seen[neighbour] = true
                        component[#component + 1] = neighbour
                    end
                end
                index = index + 1
            end
            table.sort(component)
            components[#components + 1] = component
        end
    end
    table.sort(components, function(a, b)
        if #a ~= #b then return #a > #b end
        return a[1] < b[1]
    end)
    return components
end

function Graph:greedy_clique(candidates)
    local remaining = {}
    for _, id in ipairs(candidates) do remaining[#remaining + 1] = id end
    local clique = {}
    while #remaining > 0 do
        table.sort(remaining, function(a, b)
            local da, db = self:degree(a), self:degree(b)
            if da ~= db then return da > db end
            return a < b
        end)
        local chosen = remaining[1]
        clique[#clique + 1] = chosen
        local next_candidates = {}
        for _, id in ipairs(remaining) do
            if self.shared[chosen][id] then
                next_candidates[#next_candidates + 1] = id
            end
        end
        remaining = next_candidates
    end
    return clique
end

function Graph:kempe_chain(assignment, start, first_slot, second_slot)
    local chain, seen = {start}, {[start] = true}
    local index = 1
    while index <= #chain do
        for neighbour in pairs(self:neighbours(chain[index])) do
            local slot = assignment[neighbour]
            if not seen[neighbour] and (slot == first_slot or slot == second_slot) then
                seen[neighbour] = true
                chain[#chain + 1] = neighbour
            end
        end
        index = index + 1
    end
    table.sort(chain)
    return chain
end

local function reachable(arrows, source, target)
    local stack, seen = {source}, {[source] = true}
    while #stack > 0 do
        local node = table.remove(stack)
        if node == target then return true end
        for _, successor in ipairs(arrows[node] or {}) do
            if not seen[successor] then
                seen[successor] = true
                stack[#stack + 1] = successor
            end
        end
    end
    return false
end

return {ConflictGraph = Graph, reachable = reachable}
