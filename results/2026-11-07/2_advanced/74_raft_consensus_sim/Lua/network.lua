local M = {TYPES = {'RV', 'RVR', 'AE', 'AER', 'TN'}, FIELDS = {'sent', 'delivered', 'inflight', 'partition', 'rule', 'loss', 'down'}, REASONS = {'partition', 'rule', 'loss', 'down'}}
M.__index = M
local function statistics()
    local result = {}
    for _, field in ipairs(M.FIELDS) do result[field] = 0 end
    return result
end
function M.new(count)
    local lines = {}
    for line in io.lines('input/network.txt') do local row = {}; for word in line:gmatch('%S+') do row[#row + 1] = word end; lines[#lines + 1] = row end
    local self = setmetatable({links = {}, groups = {}, total = statistics(), by_type = {}, queue = {}, serial = 0, count_nodes = count}, M)
    for _, kind in ipairs(M.TYPES) do self.by_type[kind] = statistics() end
    for source = 1, count do
        self.links[source], self.groups[source] = {}, 0
        for destination = 1, count do
            if source ~= destination then self.links[source][destination] = {delay = tonumber(lines[1][2]), loss = 0, passed = 0, drops = {}, stats = statistics()} end
        end
    end
    for i = 2, #lines do
        local f = lines[i]
        for source = 1, count do
            for destination = 1, count do
                local link = self.links[source][destination]
                if link and (f[2] == '*' or tonumber(f[2]) == source) and (f[3] == '*' or tonumber(f[3]) == destination) then
                    if f[1] == 'DELAY' then link.delay = tonumber(f[4])
                    elseif f[1] == 'LOSS' then link.loss = tonumber(f[4])
                    else link.drops[#link.drops + 1] = {f[4], tonumber(f[5]), tonumber(f[6])} end
                end
            end
        end
    end
    return self
end
function M:partition(groups) for i, group in ipairs(groups) do for _, node in ipairs(group) do self.groups[node] = i end end end
function M:heal() for node = 1, self.count_nodes do self.groups[node] = 0 end end
function M:separated(a, b) return self.groups[a] ~= self.groups[b] end
function M:count(message, field, amount)
    amount = amount or 1
    for _, stats in ipairs({self.total, self.by_type[message.kind], self.links[message.source][message.destination].stats}) do stats[field] = stats[field] + amount end
end
function M:send(time, source, destination, term, kind, data)
    local message = {kind = kind, source = source, destination = destination, term = term, data = data}
    self.serial = self.serial + 1
    self:count(message, 'sent')
    local link = self.links[source][destination]
    if self:separated(source, destination) then self:count(message, 'partition'); return end
    for _, drop in ipairs(link.drops) do if (drop[1] == kind or drop[1] == 'ALL') and drop[2] <= time and time <= drop[3] then self:count(message, 'rule'); return end end
    link.passed = link.passed + 1
    if link.loss > 0 and link.passed % link.loss == 0 then self:count(message, 'loss'); return end
    self:count(message, 'inflight')
    local arrival = time + link.delay
    self.queue[arrival] = self.queue[arrival] or {}
    self.queue[arrival][#self.queue[arrival] + 1] = {source = source, serial = self.serial, message = message}
end
function M:arrivals(time)
    local due = self.queue[time] or {}
    self.queue[time] = nil
    table.sort(due, function(a, b) return a.source < b.source or a.source == b.source and a.serial < b.serial end)
    local index = 0
    return function()
        index = index + 1
        if index > #due then return nil end
        local message = due[index].message
        self:count(message, 'inflight', -1)
        return message
    end
end
function M:deliver(message, up)
    if not up then self:count(message, 'down'); return false end
    if self:separated(message.source, message.destination) then self:count(message, 'partition'); return false end
    self:count(message, 'delivered')
    return true
end
return M
