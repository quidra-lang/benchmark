local Rational = require("rational")
local Intersections = require("intersections")
local Rings = require("rings")
local Graph = {}
Graph.__index = Graph

function Graph.new(first, second)
    local self = setmetatable({rings = {first, second}, nodes = {{}, {}}, initial_inside = {{}, {}}, crossings = {}, n_a = 0, n_b = 0}, Graph)
    local slots = {{}, {}}
    for side, sequence in ipairs(self.rings) do
        for r, ring in ipairs(sequence) do
            slots[side][r] = {}
            for edge = 1, #ring do slots[side][r][edge] = {} end
        end
    end
    for r, ring in ipairs(first) do
        for e, a in ipairs(ring) do
            local b = ring[e % #ring + 1]
            for s, other in ipairs(second) do
                for f, c in ipairs(other) do
                    local found = Intersections.crossing(a, b, c, other[f % #other + 1])
                    if found then
                        local crossing = {point = found.point}
                        local p = {point = found.point, side = 1, crossing = crossing}
                        local q = {point = found.point, side = 2, crossing = crossing}
                        p.other, q.other, crossing.first, crossing.second = q, p, p, q
                        local one, two = slots[1][r][e], slots[2][s][f]
                        one[#one + 1], two[#two + 1] = {n = found.t, d = found.d, node = p}, {n = found.u, d = found.d, node = q}
                    end
                end
            end
        end
    end
    for side, sequence in ipairs(self.rings) do
        for r, ring in ipairs(sequence) do
            local nodes = {}
            for e, point in ipairs(ring) do
                nodes[#nodes + 1] = {point = point, side = side, line = ring.lines[e]}
                local inserted = slots[side][r][e]
                table.sort(inserted, function(a, b) return a.n * b.d < b.n * a.d end)
                for _, slot in ipairs(inserted) do
                    slot.node.line = ring.lines[e]
                    nodes[#nodes + 1] = slot.node
                end
            end
            local state = Rings.interior(self.rings[3 - side], ring[1])
            self.initial_inside[side][r] = state
            for index, node in ipairs(nodes) do
                node.previous, node.next = nodes[(index - 2) % #nodes + 1], nodes[index % #nodes + 1]
                if node.crossing then node.entering, state = not state, not state end
            end
            self.nodes[side][r] = nodes
        end
    end
    for _, nodes in ipairs(self.nodes[1]) do
        for _, node in ipairs(nodes) do if node.crossing then self.crossings[#self.crossings + 1] = node.crossing end end
    end
    for _, state in ipairs(self.initial_inside[1]) do if state then self.n_a = self.n_a + 1 end end
    for _, state in ipairs(self.initial_inside[2]) do if state then self.n_b = self.n_b + 1 end end
    return self
end

local function append_node(ring, node, forward)
    local line = forward and node.line or node.previous.line
    ring[#ring + 1] = node.point
    ring.lines[#ring.lines + 1] = forward and line or {a = line.b, b = line.a}
end

function Graph:traverse(invert_first, invert_second)
    local inverted, visited, result = {invert_first, invert_second}, {}, {}
    for _, start in ipairs(self.crossings) do
        if not visited[start] then
            local ring, current = {lines = {}}, start.first
            while true do
                visited[current.crossing] = true
                local forward = current.entering ~= inverted[current.side]
                append_node(ring, current, forward)
                local stopped = forward and current.next or current.previous
                while not stopped.crossing do
                    append_node(ring, stopped, forward)
                    stopped = forward and stopped.next or stopped.previous
                end
                if stopped.crossing == start then break end
                current = stopped.other
            end
            result[#result + 1] = ring
        end
    end
    for side, sequence in ipairs(self.rings) do
        for r, ring in ipairs(sequence) do
            local crossed = false
            for _, node in ipairs(self.nodes[side][r]) do if node.crossing then crossed = true; break end end
            if not crossed and self.initial_inside[side][r] ~= inverted[side] then result[#result + 1] = ring end
        end
    end
    return result
end

return Graph
