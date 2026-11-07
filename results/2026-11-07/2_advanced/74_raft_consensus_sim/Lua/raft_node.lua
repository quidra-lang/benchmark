local M = {}
M.__index = M
local statistics = {'elections', 'leader_terms', 'votes_granted', 'leader_ticks', 'ae_ok', 'ae_fail', 'appended', 'truncated', 'applies'}
function M:cancel_transfer() self.transfer_target, self.transfer_sent, self.transfer_deadline = nil, false, nil end
function M:reset_volatile()
    self.role, self.commit, self.applied, self.store, self.known_leader = 'FOLLOWER', 0, 0, {}, nil
    self.votes, self.election_deadline, self.election_record = {}, nil, nil
    self.next, self.match, self.heartbeat_deadline, self.quorum_deadline, self.heard = {}, {}, nil, nil, {}
    self:cancel_transfer()
end
function M.new(number)
    local self = setmetatable({number = number, term = 0, voted_for = nil, log = {}, up = true, stats = {}}, M)
    for _, key in ipairs(statistics) do self.stats[key] = 0 end
    self:reset_volatile()
    return self
end
function M:crash() self.up = false; self:reset_volatile() end
function M:last_term() return #self.log > 0 and self.log[#self.log].term or 0 end
function M:term_at(index) return index == 0 and 0 or self.log[index].term end
function M:accepts_log(last_index, last_term)
    local own_term = self:last_term()
    return last_term > own_term or last_term == own_term and last_index >= #self.log
end
function M.entry(term, command, request) return {term = term, command = command, request = request} end
function M.copy_entry(entry)
    local command = {}
    for i, value in ipairs(entry.command) do command[i] = value end
    return M.entry(entry.term, command, entry.request)
end
function M.same_entry(a, b)
    if a.term ~= b.term or a.request ~= b.request or #a.command ~= #b.command then return false end
    for i, value in ipairs(a.command) do if value ~= b.command[i] then return false end end
    return true
end
function M.apply_command(store, command)
    local operation, key = command[1], command[2]
    if operation == 'NOOP' then return nil end
    if operation == 'SET' then store[key] = command[3]; return 'ok' end
    if operation == 'ADD' then store[key] = (store[key] or 0) + command[3]; return store[key] end
    if operation == 'DEL' then if store[key] ~= nil then store[key] = nil; return 'deleted' end; return 'missing' end
    return store[key] ~= nil and store[key] or 'missing'
end
return M
