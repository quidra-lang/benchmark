package.path = 'Lua/?.lua;' .. package.path
local Checker = require('checker')
local cluster = require('cluster')
local Minstd = require('minstd')
local Network = require('network')
local Node = require('raft_node')
local function count(set) local total = 0; for _ in pairs(set) do total = total + 1 end; return total end
local function keys(set)
    local result = {}
    for key in pairs(set) do result[#result + 1] = key end
    table.sort(result)
    return result
end
local function copy(values)
    local result = {}
    for key, value in pairs(values) do result[key] = value end
    return result
end
local function node_set(set)
    local names = {}
    for _, number in ipairs(keys(set)) do names[#names + 1] = 'n' .. number end
    return #names == 0 and '-' or table.concat(names, ',')
end
local function command_text(command) return table.concat(command, ' ') end
local Simulator = {}
Simulator.__index = Simulator
function Simulator.new(settings, controls, requests)
    local self = setmetatable({settings = settings, nodes = {}, network = Network.new(settings.nodes), random = Minstd.new(settings.seed), checker = Checker.new(), controls = {}, requests = requests,
        attempt_queue = {}, time = 0, trace = {}, elections = {}, leaders = {}, timelines = {}, leader_ticks = 0, multi_ticks = 0, gaps = {}}, Simulator)
    for number = 1, settings.nodes do self.nodes[number] = Node.new(number) end
    for _, event in ipairs(controls) do self.controls[event.time] = self.controls[event.time] or {}; self.controls[event.time][#self.controls[event.time] + 1] = event end
    for _, request in ipairs(requests) do self.attempt_queue[request.scheduled] = self.attempt_queue[request.scheduled] or {}; self.attempt_queue[request.scheduled][#self.attempt_queue[request.scheduled] + 1] = request end
    return self
end
function Simulator:majority(number) return 2 * number > self.settings.nodes end
function Simulator:write_trace(text) self.trace[#self.trace + 1] = self.time .. ' ' .. text end
function Simulator:set_election_timer(node) node.election_deadline = self.time + self.random:between(self.settings.election_min, self.settings.election_max) end
function Simulator:send(node, destination, kind, data) self.network:send(self.time, node.number, destination, node.term, kind, data) end
function Simulator:send_append(node, destination)
    local previous, entries = node.next[destination] - 1, {}
    for index = previous + 1, math.min(previous + self.settings.batch, #node.log) do entries[#entries + 1] = Node.copy_entry(node.log[index]) end
    self:send(node, destination, 'AE', {previous = previous, previous_term = node:term_at(previous), entries = entries, commit = node.commit})
end
function Simulator:broadcast_append(node) for _, other in ipairs(self.nodes) do if other ~= node then self:send_append(node, other.number) end end end
function Simulator:end_leadership(node, reason)
    local record = self.leaders[node.term]
    record.ended, record.reason, record.commit = self.time, reason, node.commit
    node:cancel_transfer()
end
function Simulator:control(event)
    local kind, arguments = event.kind, event.arguments
    if kind == 'CRASH' then
        local node = self.nodes[arguments[1]]
        self:write_trace('CRASH n' .. node.number .. ' ' .. node.role .. ' term ' .. node.term)
        if node.role == 'LEADER' then self:end_leadership(node, 'CRASH') end
        node:crash()
    elseif kind == 'RESTART' then
        local node = self.nodes[arguments[1]]
        node.up = true
        self:set_election_timer(node)
        self:write_trace('RESTART n' .. node.number .. ' term ' .. node.term .. ' length ' .. #node.log .. ' deadline ' .. node.election_deadline)
    elseif kind == 'PARTITION' then
        self.network:partition(arguments)
        local groups = {}
        for _, group in ipairs(arguments) do local set = {}; for _, number in ipairs(group) do set[number] = true end; groups[#groups + 1] = node_set(set) end
        self:write_trace('PARTITION ' .. table.concat(groups, ' '))
    elseif kind == 'HEAL' then self.network:heal(); self:write_trace('HEAL')
    else self:start_transfer(self.nodes[arguments[1]], arguments[2]) end
end
function Simulator:attempt(request)
    request.attempts = request.attempts + 1
    local destination, redirected, node, reason = request.destination, 0, nil, nil
    while true do
        node = self.nodes[destination]
        if not node.up then reason = 'down'; break end
        if node.role == 'LEADER' then
            if node.transfer_target then reason = 'transfer'; break end
            node.log[#node.log + 1] = Node.entry(node.term, request.command, request.number)
            self.leaders[node.term].appended = self.leaders[node.term].appended + 1
            request.accepted, request.scheduled = {#node.log, node.term}, nil
            self:write_trace('ACCEPT r' .. request.number .. ' n' .. node.number .. ' index ' .. #node.log .. ' term ' .. node.term)
            return
        end
        if not node.known_leader or redirected >= self.settings.nodes - 1 then reason = 'noleader'; break end
        destination = node.known_leader
        self:write_trace('REDIRECT r' .. request.number .. ' n' .. node.number .. ' n' .. destination)
        redirected, request.redirects = redirected + 1, request.redirects + 1
    end
    local prefix = 'REJECT r' .. request.number .. ' n' .. node.number .. ' ' .. reason
    if request.attempts < self.settings.attempts then
        request.destination, request.scheduled = node.number % self.settings.nodes + 1, self.time + self.settings.retry
        self.attempt_queue[request.scheduled] = self.attempt_queue[request.scheduled] or {}
        self.attempt_queue[request.scheduled][#self.attempt_queue[request.scheduled] + 1] = request
        self:write_trace(prefix .. ' retry n' .. request.destination .. ' at ' .. request.scheduled)
    else request.abandoned, request.scheduled = true, nil; self:write_trace(prefix .. ' giveup') end
end
function Simulator:start_election(node, trigger)
    node.term, node.role, node.voted_for, node.votes, node.known_leader = node.term + 1, 'CANDIDATE', node.number, {[node.number] = true}, nil
    self:set_election_timer(node)
    node.stats.elections = node.stats.elections + 1
    local record = {time = self.time, node = node.number, term = node.term, trigger = trigger, votes = node.votes}
    node.election_record, self.elections[#self.elections + 1] = record, record
    self:write_trace('ELECTION n' .. node.number .. ' term ' .. node.term .. ' last ' .. #node.log .. '/' .. node:last_term() .. ' deadline ' .. node.election_deadline)
    for _, other in ipairs(self.nodes) do if other ~= node then self:send(node, other.number, 'RV', {last_index = #node.log, last_term = node:last_term()}) end end
end
function Simulator:vote_request(node, message)
    local reason
    if message.term < node.term then reason = 'term'
    elseif node.voted_for and node.voted_for ~= message.source then reason = 'voted'
    elseif not node:accepts_log(message.data.last_index, message.data.last_term) then reason = 'log' end
    if not reason then
        node.voted_for, node.stats.votes_granted = message.source, node.stats.votes_granted + 1
        self:set_election_timer(node)
        self:write_trace('VOTE n' .. node.number .. ' n' .. message.source .. ' term ' .. node.term .. ' deadline ' .. node.election_deadline)
    else self:write_trace('DENY n' .. node.number .. ' n' .. message.source .. ' term ' .. node.term .. ' ' .. reason) end
    self:send(node, message.source, 'RVR', {granted = reason == nil})
end
function Simulator:vote_response(node, message)
    if node.role ~= 'CANDIDATE' or message.term ~= node.term or not message.data.granted then return end
    node.votes[message.source] = true
    if self:majority(count(node.votes)) then self:become_leader(node) end
end
function Simulator:become_leader(node)
    node.role, node.known_leader, node.next, node.match = 'LEADER', node.number, {}, {}
    for _, other in ipairs(self.nodes) do if other ~= node then node.next[other.number], node.match[other.number] = #node.log + 1, 0 end end
    node.log[#node.log + 1] = Node.entry(node.term, {'NOOP'}, 0)
    node.stats.leader_terms, node.election_record.won = node.stats.leader_terms + 1, self.time
    self.checker:leader(node)
    self.leaders[node.term] = {node = node.number, elected = self.time, votes = copy(node.votes), appended = 1}
    self:write_trace('LEADER n' .. node.number .. ' term ' .. node.term .. ' votes ' .. node_set(node.votes) .. ' noop ' .. #node.log)
    self:broadcast_append(node)
    node.heartbeat_deadline, node.quorum_deadline, node.heard = self.time + self.settings.heartbeat, self.time + self.settings.quorum, {}
end
function Simulator:truncate(node, first)
    local removed = {}
    for index = first, #node.log do removed[#removed + 1] = node.log[index] end
    for index = #node.log, first, -1 do node.log[index] = nil end
    node.stats.truncated = node.stats.truncated + #removed
    self.checker:truncate(first, removed)
    self:write_trace('TRUNCATE n' .. node.number .. ' from ' .. first .. ' removed ' .. #removed)
end
function Simulator:append_request(node, message)
    if message.term < node.term then self:send(node, message.source, 'AER', {success = false, match = 0}); return end
    if node.role == 'CANDIDATE' then node.role = 'FOLLOWER'; self:write_trace('YIELD n' .. node.number .. ' term ' .. node.term .. ' n' .. message.source) end
    node.known_leader = message.source
    self:set_election_timer(node)
    local previous = message.data.previous
    if previous > #node.log or node:term_at(previous) ~= message.data.previous_term then
        node.stats.ae_fail = node.stats.ae_fail + 1
        self:send(node, message.source, 'AER', {success = false, match = previous > #node.log and #node.log or previous - 1})
        return
    end
    node.stats.ae_ok = node.stats.ae_ok + 1
    for offset, entry in ipairs(message.data.entries) do
        local index = previous + offset
        if index <= #node.log and node:term_at(index) ~= entry.term then self:truncate(node, index) end
        if index > #node.log then node.log[#node.log + 1] = entry; node.stats.appended = node.stats.appended + 1 end
    end
    local confirmed = previous + #message.data.entries
    local commit = math.min(message.data.commit, confirmed)
    if commit > node.commit then self:advance_commit(node, commit) end
    self:send(node, message.source, 'AER', {success = true, match = confirmed})
end
function Simulator:append_response(node, message)
    if node.role ~= 'LEADER' or message.term ~= node.term then return end
    local source, confirmed = message.source, message.data.match
    node.heard[source] = true
    if message.data.success then
        node.match[source], node.next[source] = math.max(node.match[source], confirmed), math.max(node.next[source], confirmed + 1)
        self:check_commit(node)
        if source == node.transfer_target and not node.transfer_sent and node.match[source] == #node.log then self:send_timeout_now(node)
        elseif node.next[source] <= #node.log then self:send_append(node, source) end
    else
        node.next[source] = math.max(node.match[source] + 1, math.min(node.next[source] - 1, confirmed + 1))
        self:write_trace('BACKTRACK n' .. node.number .. ' n' .. source .. ' next ' .. node.next[source])
        self:send_append(node, source)
    end
end
function Simulator:check_commit(node)
    for index = #node.log, node.commit + 1, -1 do
        if node:term_at(index) ~= node.term then return end
        local replicated = 1
        for _, other in ipairs(self.nodes) do if other ~= node and node.match[other.number] >= index then replicated = replicated + 1 end end
        if self:majority(replicated) then self:write_trace('COMMIT n' .. node.number .. ' ' .. (node.commit + 1) .. '-' .. index .. ' term ' .. node.term); self:advance_commit(node, index); return end
    end
end
function Simulator:advance_commit(node, index)
    for position = node.commit + 1, index do self.checker:commit(position, node:term_at(position), self.time) end
    node.commit = index
    local first = node.applied + 1
    for position = first, index do
        local entry = node.log[position]
        local result = Node.apply_command(node.store, entry.command)
        node.stats.applies = node.stats.applies + 1
        self.checker:apply(position, entry, result)
    end
    node.applied = index
    self:write_trace('APPLY n' .. node.number .. ' ' .. first .. '-' .. index)
end
function Simulator:receive(message)
    local node = self.nodes[message.destination]
    if message.term > node.term then
        local role = node.role
        self:write_trace('TERM n' .. node.number .. ' ' .. node.term .. '->' .. message.term .. ' ' .. message.kind .. ' n' .. message.source .. ' ' .. role)
        if role == 'LEADER' then self:end_leadership(node, 'STEPDOWN') end
        node.term, node.voted_for, node.known_leader, node.role = message.term, nil, nil, 'FOLLOWER'
        if role == 'LEADER' then self:set_election_timer(node) end
    end
    if message.kind == 'RV' then self:vote_request(node, message)
    elseif message.kind == 'RVR' then self:vote_response(node, message)
    elseif message.kind == 'AE' then self:append_request(node, message)
    elseif message.kind == 'AER' then self:append_response(node, message)
    elseif message.term ~= node.term or node.role ~= 'FOLLOWER' then self:write_trace('IGNORE n' .. node.number .. ' TN n' .. message.source .. ' term ' .. message.term)
    else self:start_election(node, 'transfer') end
end
function Simulator:start_transfer(node, destination)
    local prefix = 'TRANSFER n' .. node.number .. ' n' .. destination
    if not node.up or node.role ~= 'LEADER' or node.transfer_target or node.number == destination then self:write_trace(prefix .. ' ignored'); return end
    self:write_trace(prefix .. ' start match ' .. node.match[destination] .. '/' .. #node.log)
    node.transfer_target, node.transfer_sent, node.transfer_deadline = destination, false, self.time + self.settings.election_min
    if node.match[destination] == #node.log then self:send_timeout_now(node) else self:send_append(node, destination) end
end
function Simulator:send_timeout_now(node)
    self:write_trace('TIMEOUTNOW n' .. node.number .. ' n' .. node.transfer_target .. ' term ' .. node.term .. ' index ' .. #node.log)
    node.transfer_sent = true
    self:send(node, node.transfer_target, 'TN', {})
end
function Simulator:timers(node)
    if node.role == 'LEADER' then
        if node.quorum_deadline == self.time then
            if not self:majority(1 + count(node.heard)) then
                self:write_trace('STEPDOWN n' .. node.number .. ' term ' .. node.term .. ' heard ' .. node_set(node.heard))
                self:end_leadership(node, 'QUORUM')
                node.role, node.known_leader = 'FOLLOWER', nil
                self:set_election_timer(node)
                return
            end
            node.heard, node.quorum_deadline = {}, self.time + self.settings.quorum
        end
        if node.transfer_target and node.transfer_deadline == self.time then self:write_trace('TRANSFER n' .. node.number .. ' n' .. node.transfer_target .. ' abort'); node:cancel_transfer() end
        if node.heartbeat_deadline == self.time then self:broadcast_append(node); node.heartbeat_deadline = self.time + self.settings.heartbeat end
    elseif node.election_deadline == self.time then self:start_election(node, 'timeout') end
end
function Simulator:end_of_tick()
    self.checker:check_logs(self.nodes)
    local leader_count = 0
    for _, node in ipairs(self.nodes) do if node.up and node.role == 'LEADER' then leader_count = leader_count + 1; node.stats.leader_ticks = node.stats.leader_ticks + 1 end end
    if leader_count > 0 then
        self.leader_ticks = self.leader_ticks + 1
        if leader_count >= 2 then self.multi_ticks = self.multi_ticks + 1 end
        if self.gap_start ~= nil then self.gaps[#self.gaps + 1], self.gap_start = {self.gap_start, self.time - 1}, nil end
    elseif self.gap_start == nil then self.gap_start = self.time end
    if self.time % self.settings.sample == 0 then
        local fields = {}
        for _, node in ipairs(self.nodes) do fields[#fields + 1] = (node.up and node.role:sub(1, 1) or 'D') .. node.term end
        self.timelines[#self.timelines + 1] = 'TIMELINE ' .. self.time .. ' ' .. table.concat(fields, ' ')
    end
end
function Simulator:run()
    for _, node in ipairs(self.nodes) do self:set_election_timer(node); self:write_trace('START n' .. node.number .. ' deadline ' .. node.election_deadline) end
    for time = 0, self.settings.finish do
        self.time = time
        for _, event in ipairs(self.controls[time] or {}) do self:control(event) end
        local attempts = self.attempt_queue[time] or {}
        self.attempt_queue[time] = nil
        table.sort(attempts, function(a, b) return a.number < b.number end)
        for _, request in ipairs(attempts) do self:attempt(request) end
        for message in self.network:arrivals(time) do if self.network:deliver(message, self.nodes[message.destination].up) then self:receive(message) end end
        for _, node in ipairs(self.nodes) do if node.up then self:timers(node) end end
        self:end_of_tick()
    end
    if self.gap_start ~= nil then self.gaps[#self.gaps + 1] = {self.gap_start, self.settings.finish} end
    self:finish_statistics()
end

function Simulator:finish_statistics()
    self.maximum_term, self.committed_count = 0, #self.checker.committed
    local needed = {}
    for _, node in ipairs(self.nodes) do self.maximum_term = math.max(self.maximum_term, node.term); needed[node.applied] = true end
    self.reference_states, self.reference_state = {[0] = {}}, {}
    for index = 1, self.committed_count do
        Node.apply_command(self.reference_state, self.checker.applied[index].entry.command)
        if needed[index] then self.reference_states[index] = copy(self.reference_state) end
    end
    self.status_counts, self.latencies, self.key_requests, self.key_committed = {}, {}, {}, {}
    for _, request in ipairs(self.requests) do
        local key = request.command[2]
        self.key_requests[key] = (self.key_requests[key] or 0) + 1
        if request.accepted then
            local index, term = table.unpack(request.accepted)
            local committed = self.checker.committed[index]
            if committed and committed.term == term then
                request.status, request.latency, request.result = 'COMMITTED', committed.time - request.time, self.checker.applied[index].result
                self.latencies[#self.latencies + 1] = request.latency
                self.key_committed[key] = (self.key_committed[key] or 0) + 1
            else
                request.status = 'LOST'
                for _, node in ipairs(self.nodes) do if #node.log >= index and node:term_at(index) == term then request.status = 'UNCOMMITTED'; break end end
            end
        elseif request.abandoned then request.status = 'FAILED'
        else request.status = 'WAITING' end
        self.status_counts[request.status] = (self.status_counts[request.status] or 0) + 1
    end
end
function Simulator:leader_lines()
    local lines, by_term = {}, {}
    for _, record in ipairs(self.elections) do
        local outcome = record.won ~= nil and 'WON ' .. record.won or 'LOST'
        lines[#lines + 1] = 'ELECTION ' .. record.time .. ' n' .. record.node .. ' term ' .. record.term .. ' trigger ' .. record.trigger .. ' votes ' .. count(record.votes) .. ' ' .. outcome
        by_term[record.term] = by_term[record.term] or {}
        by_term[record.term][#by_term[record.term] + 1] = record
    end
    for term = 1, self.maximum_term do
        local elections, candidates = by_term[term] or {}, {}
        for _, record in ipairs(elections) do candidates[record.node] = true end
        local record = self.leaders[term]
        if not record then lines[#lines + 1] = 'TERM ' .. term .. ' NONE candidates ' .. node_set(candidates)
        else
            local finish, reason, commit
            if record.ended == nil then finish, reason, commit = '-', 'ACTIVE', self.nodes[record.node].commit else finish, reason, commit = record.ended, record.reason, record.commit end
            local start = elections[1].time
            lines[#lines + 1] = 'TERM ' .. term .. ' LEADER n' .. record.node .. ' elected ' .. record.elected .. ' votes ' .. node_set(record.votes) .. ' ended ' .. finish .. ' ' .. reason .. ' appended ' .. record.appended .. ' commit ' .. commit .. ' candidates ' .. node_set(candidates) .. ' started ' .. start .. ' wait ' .. (record.elected - start)
        end
    end
    for _, node in ipairs(self.nodes) do local statistics = node.stats; lines[#lines + 1] = 'NODE n' .. node.number .. ' elections ' .. statistics.elections .. ' leader_terms ' .. statistics.leader_terms .. ' leader_ticks ' .. statistics.leader_ticks .. ' votes_granted ' .. statistics.votes_granted end
    for _, timeline in ipairs(self.timelines) do lines[#lines + 1] = timeline end
    local longest = 0
    for _, gap in ipairs(self.gaps) do local length = gap[2] - gap[1] + 1; lines[#lines + 1] = 'GAP ' .. gap[1] .. '-' .. gap[2] .. ' length ' .. length; longest = math.max(longest, length) end
    lines[#lines + 1] = 'SUMMARY terms ' .. self.maximum_term .. ' leaders ' .. count(self.leaders) .. ' elections ' .. #self.elections .. ' leader_ticks ' .. self.leader_ticks .. ' multi_ticks ' .. self.multi_ticks .. ' ticks ' .. (self.settings.finish + 1) .. ' gaps ' .. #self.gaps .. ' longest ' .. longest
    return lines
end
function Simulator:log_lines()
    local lines, shortest = {}, #self.nodes[1].log
    for _, node in ipairs(self.nodes) do
        local status, voted = node.up and node.role or 'DOWN', node.voted_for and 'n' .. node.voted_for or '-'
        lines[#lines + 1] = 'NODE n' .. node.number .. ' ' .. status .. ' term ' .. node.term .. ' voted ' .. voted .. ' commit ' .. node.commit .. ' applied ' .. node.applied .. ' length ' .. #node.log
        for index, entry in ipairs(node.log) do lines[#lines + 1] = index .. ' ' .. entry.term .. ' ' .. command_text(entry.command) .. (entry.request ~= 0 and ' r' .. entry.request or '') end
        shortest = math.min(shortest, #node.log)
    end
    local prefix = 0
    for index = 1, shortest do
        local same = true
        for node = 2, #self.nodes do if not Node.same_entry(self.nodes[1].log[index], self.nodes[node].log[index]) then same = false; break end end
        if not same then break end
        prefix = prefix + 1
    end
    lines[#lines + 1] = 'AGREE prefix ' .. prefix .. ' committed ' .. self.committed_count
    for _, node in ipairs(self.nodes) do
        local common = 0
        for index = 1, math.min(#node.log, self.committed_count) do if node:term_at(index) ~= self.checker.committed[index].term then break end; common = index end
        local statistics = node.stats
        lines[#lines + 1] = 'DIFF n' .. node.number .. ' common ' .. common .. ' behind ' .. (self.committed_count - common) .. ' extra ' .. (#node.log - common) .. ' ae_ok ' .. statistics.ae_ok .. ' ae_fail ' .. statistics.ae_fail .. ' appended ' .. statistics.appended .. ' truncated ' .. statistics.truncated .. ' applies ' .. statistics.applies
    end
    return lines
end
function Simulator:request_line(request)
    local text = 'REQUEST r' .. request.number .. ' at ' .. request.time .. ' n' .. request.initial_destination .. ' ' .. command_text(request.command) .. ' attempts ' .. request.attempts .. ' redirects ' .. request.redirects .. ' '
    if request.accepted then
        text = text .. request.status .. ' index ' .. request.accepted[1] .. ' term ' .. request.accepted[2]
        if request.status == 'COMMITTED' then text = text .. ' latency ' .. request.latency .. ' result ' .. request.result end
    elseif request.status == 'FAILED' then text = text .. 'FAILED'
    else text = text .. 'WAITING next ' .. request.scheduled end
    return text
end
local function same_store(a, b)
    for key, value in pairs(a) do if b[key] ~= value then return false end end
    for key, value in pairs(b) do if a[key] ~= value then return false end end
    return true
end
function Simulator:state_lines()
    local lines = {}
    for _, node in ipairs(self.nodes) do
        lines[#lines + 1] = 'NODE n' .. node.number .. ' ' .. (node.up and 'UP' or 'DOWN') .. ' applied ' .. node.applied .. ' keys ' .. count(node.store) .. ' replay ' .. (same_store(node.store, self.reference_states[node.applied]) and 'match' or 'mismatch')
        for _, key in ipairs(keys(node.store)) do lines[#lines + 1] = key .. ' ' .. node.store[key] end
    end
    for _, request in ipairs(self.requests) do lines[#lines + 1] = self:request_line(request) end
    for _, key in ipairs(keys(self.key_requests)) do
        local value = self.reference_state[key]
        lines[#lines + 1] = 'KEY ' .. key .. ' requests ' .. self.key_requests[key] .. ' committed ' .. (self.key_committed[key] or 0) .. ' final ' .. (value ~= nil and value or 'missing')
    end
    local statuses = {}
    for _, name in ipairs({'COMMITTED', 'UNCOMMITTED', 'LOST', 'FAILED', 'WAITING'}) do statuses[#statuses + 1] = name:lower() .. ' ' .. (self.status_counts[name] or 0) end
    lines[#lines + 1] = 'REQUESTS total ' .. #self.requests .. ' ' .. table.concat(statuses, ' ')
    local total, minimum, maximum = 0, self.latencies[1] or 0, self.latencies[1] or 0
    for _, latency in ipairs(self.latencies) do total, minimum, maximum = total + latency, math.min(minimum, latency), math.max(maximum, latency) end
    lines[#lines + 1] = 'LATENCY count ' .. #self.latencies .. ' total ' .. total .. ' min ' .. minimum .. ' max ' .. maximum
    return lines
end
local function message_statistics(statistics)
    local result = {}
    for _, field in ipairs(Network.FIELDS) do result[#result + 1] = field .. ' ' .. statistics[field] end
    return table.concat(result, ' ')
end
function Simulator:safety_lines()
    local lines = self.checker:lines(self.maximum_term)
    lines[#lines + 1] = 'MESSAGES ' .. message_statistics(self.network.total)
    for _, kind in ipairs(Network.TYPES) do lines[#lines + 1] = 'TYPE ' .. kind .. ' ' .. message_statistics(self.network.by_type[kind]) end
    for source = 1, self.settings.nodes do
        for destination = 1, self.settings.nodes do
            if source ~= destination then
                local link, dropped = self.network.links[source][destination], 0
                for _, reason in ipairs(Network.REASONS) do dropped = dropped + link.stats[reason] end
                lines[#lines + 1] = 'LINK n' .. source .. '->n' .. destination .. ' delay ' .. link.delay .. ' loss ' .. link.loss .. ' sent ' .. link.stats.sent .. ' delivered ' .. link.stats.delivered .. ' dropped ' .. dropped
            end
        end
    end
    lines[#lines + 1] = 'DRAWS ' .. self.random.draws
    local safe = true
    for _, property in ipairs(Checker.PROPERTIES) do if self.checker.violations[property] ~= 0 then safe = false end end
    lines[#lines + 1] = safe and 'RESULT SAFE' or 'RESULT UNSAFE'
    return lines
end
local settings = cluster.read_settings()
local controls, requests = cluster.read_script()
local simulation = Simulator.new(settings, controls, requests)
simulation:run()
for _, output in ipairs({{'trace.txt', simulation.trace}, {'leaders.txt', simulation:leader_lines()}, {'logs.txt', simulation:log_lines()}, {'state.txt', simulation:state_lines()}, {'safety.txt', simulation:safety_lines()}}) do
    local file = assert(io.open('output/' .. output[1], 'wb'))
    file:write(table.concat(output[2], '\n'), '\n')
    file:close()
end
