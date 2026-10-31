local clocks = require('clocks')
local processes = require('processes')
local M = {}
function M.new(name, start, size)
    local states = {}
    for p = 1, size do
        states[p] = {}
        for q = 1, size do states[p][q] = {} end
    end
    return {name = name, start = start, records = {}, states = states, markers = {}, accepted = 0, ignored = {}}
end
function M.record(snapshot, process, p, now, reason)
    local pending = {}
    for i, copy in ipairs(process.holdback) do pending[i] = copy end
    snapshot.records[p] = {time = now, reason = reason, balance = process.balance, lamport = process.lamport,
        vector = clocks.copy(process.vector), pending = pending}
end
function M.accept(snapshot, source, destination, now, size)
    local marker = snapshot.markers[source][destination]
    marker.accepted = now
    snapshot.accepted = snapshot.accepted + 1
    if snapshot.accepted == size * (size - 1) then snapshot.complete = now end
end
function M.cut(snapshot, size)
    local result = {}
    for p = 1, size do result[p] = snapshot.records[p].vector[p] end
    return result
end
function M.details(cut, states, copies)
    local orphans, transit, balances = {}, {}, 0
    for _, copy in ipairs(copies) do
        local sent = copy.send_event.local_number <= cut[copy.source]
        local received = copy.recv_event and copy.recv_event.local_number <= cut[copy.destination]
        if received and not sent then orphans[#orphans + 1] = copy end
        if sent and not received then transit[#transit + 1] = copy end
    end
    for p, process in ipairs(states) do balances = balances + processes.balance(process, cut[p]) end
    local money = balances
    for _, copy in ipairs(transit) do money = money + copy.amount end
    return {orphans = orphans, transit = transit, balances = balances, money = money, consistent = #orphans == 0}
end
function M.recorded(snapshot, order)
    local entries, pending = {}, {}
    for _, pair in ipairs(order) do
        for _, copy in ipairs(snapshot.states[pair[1]][pair[2]]) do entries[#entries + 1] = copy end
    end
    for _, record in ipairs(snapshot.records) do for _, copy in ipairs(record.pending) do pending[#pending + 1] = copy end end
    return entries, pending
end
function M.match(entries, pending, transit)
    local counts = {}
    for _, list in ipairs({entries, pending}) do
        for _, copy in ipairs(list) do counts[copy] = (counts[copy] or 0) + 1 end
    end
    for _, copy in ipairs(transit) do counts[copy] = (counts[copy] or 0) - 1 end
    for _, count in pairs(counts) do if count ~= 0 then return false end end
    return true
end
function M.vector_consistent(snapshot, cut)
    for _, record in ipairs(snapshot.records) do if not clocks.less_equal(record.vector, cut) then return false end end
    return true
end
function M.label(copy, names) return 'm' .. copy.message.id .. '->' .. names[copy.destination] end
return M
