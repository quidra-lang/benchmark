local Node = require('raft_node')
local M = {PROPERTIES = {'ELECTION_SAFETY', 'LEADER_COMPLETENESS', 'LOG_MATCHING', 'STATE_MACHINE_SAFETY', 'COMMITTED_KEPT'}}
M.__index = M
local function count(values) local result = 0; for _ in pairs(values) do result = result + 1 end; return result end
function M.new()
    local self = setmetatable({violations = {}, leaders = {}, committed = {}, applied = {}, elected = 0, log_checks = 0, pair_checks = 0, applies = 0, truncations = 0, removed = 0}, M)
    for _, name in ipairs(M.PROPERTIES) do self.violations[name] = 0 end
    return self
end
function M:leader(node)
    self.elected = self.elected + 1
    if self.leaders[node.term] == nil then self.leaders[node.term] = node.number
    elseif self.leaders[node.term] ~= node.number then self.violations.ELECTION_SAFETY = self.violations.ELECTION_SAFETY + 1 end
    for index, record in pairs(self.committed) do
        if index > #node.log or node:term_at(index) ~= record.term then self.violations.LEADER_COMPLETENESS = self.violations.LEADER_COMPLETENESS + 1; break end
    end
end
function M:commit(index, term, time) if not self.committed[index] then self.committed[index] = {term = term, time = time} end end
function M:apply(index, entry, result)
    self.applies = self.applies + 1
    if not self.applied[index] then self.applied[index] = {entry = entry, result = result}
    elseif not Node.same_entry(self.applied[index].entry, entry) then self.violations.STATE_MACHINE_SAFETY = self.violations.STATE_MACHINE_SAFETY + 1 end
end
function M:truncate(first, entries)
    self.truncations, self.removed = self.truncations + 1, self.removed + #entries
    for offset, entry in ipairs(entries) do local record = self.committed[first + offset - 1]; if record and record.term == entry.term then self.violations.COMMITTED_KEPT = self.violations.COMMITTED_KEPT + 1 end end
end
function M:check_logs(nodes)
    self.log_checks = self.log_checks + 1
    for i = 1, #nodes do
        for j = i + 1, #nodes do
            self.pair_checks = self.pair_checks + 1
            local first, second, greatest = nodes[i], nodes[j], 0
            for index = math.min(#first.log, #second.log), 1, -1 do if first:term_at(index) == second:term_at(index) then greatest = index; break end end
            for index = 1, greatest do if not Node.same_entry(first.log[index], second.log[index]) then self.violations.LOG_MATCHING = self.violations.LOG_MATCHING + 1; break end end
        end
    end
end
function M:lines(maximum_term)
    local details = {'terms ' .. maximum_term .. ' leaders ' .. count(self.leaders) .. ' elected ' .. self.elected,
        'checks ' .. self.elected .. ' committed ' .. #self.committed, 'checks ' .. self.log_checks .. ' pairs ' .. self.pair_checks,
        'applies ' .. self.applies .. ' indices ' .. #self.applied, 'truncations ' .. self.truncations .. ' removed ' .. self.removed}
    local result = {}
    for i, name in ipairs(M.PROPERTIES) do local violations = self.violations[name]; result[#result + 1] = name .. ' ' .. (violations == 0 and 'OK' or 'FAIL') .. ' violations ' .. violations .. ' ' .. details[i] end
    return result
end
return M
