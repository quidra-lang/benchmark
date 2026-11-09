local Topology = require("topology")
local Simulator = {}
Simulator.__index = Simulator

local function less(first, second)
    if first.arrival ~= second.arrival then return first.arrival < second.arrival end
    if first.receiver ~= second.receiver then return first.receiver < second.receiver end
    if first.sender ~= second.sender then return first.sender < second.sender end
    return first.serial < second.serial
end

function Simulator.new()
    return setmetatable({heap = {}, serial = 0}, Simulator)
end

function Simulator:push(message)
    local heap, index = self.heap, #self.heap + 1
    while index > 1 do
        local parent = index // 2
        if not less(message, heap[parent]) then break end
        heap[index], index = heap[parent], parent
    end
    heap[index] = message
end

function Simulator:send(time, sender, receiver, link, prefix, content)
    self.serial = self.serial + 1
    local message = {serial = self.serial, sender = sender, receiver = receiver, link = link,
        prefix = prefix, content = content, arrival = time + link.delay}
    self:push(message)
    return message
end

function Simulator:next_time()
    return self.heap[1] and self.heap[1].arrival
end

function Simulator:take()
    local heap, result = self.heap, self.heap[1]
    local last = table.remove(heap)
    if #heap > 0 then
        local index = 1
        while index * 2 <= #heap do
            local child = index * 2
            if child < #heap and less(heap[child + 1], heap[child]) then child = child + 1 end
            if not less(heap[child], last) then break end
            heap[index], index = heap[child], child
        end
        heap[index] = last
    end
    return result
end

function Simulator:ordered()
    local result = {}
    for i, message in ipairs(self.heap) do result[i] = message end
    table.sort(result, less)
    return result
end

function Simulator:remove_link(link)
    local ordered, removed = self:ordered(), {}
    self.heap = {}
    for _, message in ipairs(ordered) do
        if message.link == link then removed[#removed + 1] = message else self:push(message) end
    end
    return removed
end

local function event(time, text)
    local fields = Topology.words(text)
    local kind = (fields[1] == "LINK" or fields[1] == "POLICY") and fields[1] .. "_" .. fields[2] or fields[1]
    return {time = time, text = text, fields = fields, kind = kind}
end

function Simulator.events()
    local events = {event(0, "INITIAL")}
    for line in io.lines("input/events.txt") do
        local time, text = line:match("^(%d+) (.+)$")
        events[#events + 1] = event(tonumber(time), text)
    end
    return events
end

function Simulator.params()
    local lines = Topology.read("input/params.txt")
    local defaults = {customer = tonumber(lines[1][2]), peer = tonumber(lines[1][3]), provider = tonumber(lines[1][4])}
    local traces = {}
    for i = 3, #lines do
        traces[#traces + 1] = {source = tonumber(lines[i][2]), address = lines[i][3], value = Topology.address(lines[i][3])}
    end
    return defaults, tonumber(lines[2][2]), traces
end

return Simulator
