local Attempt = {}
Attempt.__index = Attempt

function Attempt.new(courses, graph, limit, candidate_slots)
    return setmetatable({courses = courses, graph = graph, limit = limit,
        candidate_slots = candidate_slots, dead_ends = 0, aborted = false, chosen = {}}, Attempt)
end

function Attempt:saturation(id, assignment)
    local slots, count = {}, 0
    for other in pairs(self.graph:neighbours(id)) do
        local slot = assignment[other]
        if slot and not slots[slot] then
            slots[slot] = true
            count = count + 1
        end
    end
    return count
end

function Attempt:search(assignment)
    local chosen, saturation, degree
    for _, id in ipairs(self.courses) do
        if not assignment[id] then
            local s, d = self:saturation(id, assignment), self.graph:degree(id)
            if not chosen or s > saturation or (s == saturation and (d > degree or (d == degree and id < chosen))) then
                chosen, saturation, degree = id, s, d
            end
        end
    end
    if not chosen then return true end
    self.chosen[#self.chosen + 1] = {chosen, saturation}
    for _, slot in ipairs(self.candidate_slots(chosen, assignment)) do
        assignment[chosen] = slot
        if self:search(assignment) then return true end
        assignment[chosen] = nil
        if self.aborted then return false end
    end
    table.remove(self.chosen)
    self.dead_ends = self.dead_ends + 1
    self.dead_end_course = chosen
    self.aborted = self.dead_ends > self.limit
    return false
end

local function greedy_numbering(order, graph)
    local numbers, maximum = {}, 0
    for _, id in ipairs(order) do
        local taken = {}
        for other in pairs(graph:neighbours(id)) do
            if numbers[other] then taken[numbers[other]] = true end
        end
        local number = 1
        while taken[number] do number = number + 1 end
        numbers[id] = number
        maximum = math.max(maximum, number)
    end
    return maximum
end

return {Attempt = Attempt, greedy_numbering = greedy_numbering}
