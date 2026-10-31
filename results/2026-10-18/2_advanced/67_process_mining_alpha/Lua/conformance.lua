local F = require('report').rational
local M = {}
function M.net(places, transitions, arcs, initial, final)
    local net = {places = places, transitions = {}, arcs = arcs, inputs = {}, outputs = {}, routes = {}, initial_marking = {}, final_marking = {}}
    local indexes = {}
    for i, p in ipairs(places) do
        indexes[p] = i; net.routes[i] = {}; net.initial_marking[i] = p == initial and 1 or 0; net.final_marking[i] = p == final and 1 or 0
    end
    net.initial, net.final = indexes[initial], indexes[final]
    for _, t in ipairs(transitions) do net.transitions[#net.transitions + 1] = t end
    table.sort(net.transitions)
    for _, t in ipairs(net.transitions) do
        net.inputs[t], net.outputs[t] = {}, {}
        for i, p in ipairs(places) do
            if arcs[p .. ':' .. t] then net.inputs[t][#net.inputs[t] + 1] = i; net.routes[i][#net.routes[i] + 1] = t end
            if arcs[t .. ':' .. p] then net.outputs[t][#net.outputs[t] + 1] = i end
        end
    end
    return net
end
function M.read()
    local places, transitions, arcs, initial, final = {}, {}, {}
    for line in io.lines('input/model.txt') do
        local kind, a, b = line:match('^(%S+) (%S+)%s*(%S*)$')
        if kind == 'PLACE' then places[#places + 1] = a elseif kind == 'TRANSITION' then transitions[#transitions + 1] = a
        elseif kind == 'ARC' then arcs[a .. ':' .. b] = true elseif kind == 'INITIAL' then initial = a else final = a end
    end
    return M.net(places, transitions, arcs, initial, final)
end
function M.enabled(net, marking, t)
    for _, i in ipairs(net.inputs[t]) do if marking[i] < 1 then return false end end
    return true
end
function M.enabled_transitions(net, marking)
    local out = {}
    for _, t in ipairs(net.transitions) do if M.enabled(net, marking, t) then out[#out + 1] = t end end
    return out
end
function M.fire(net, marking, t)
    local out = {}; for i, value in ipairs(marking) do out[i] = value end
    for _, i in ipairs(net.inputs[t]) do out[i] = out[i] - 1 end
    for _, i in ipairs(net.outputs[t]) do out[i] = out[i] + 1 end
    return out
end
function M.totals(n)
    local r = {missing = 0, remaining = 0, consumed = 0, produced = 0, skipped = 0,
        place_missing = {}, place_remaining = {}, deviating = {}, waiting = {}, routes = {}}
    for i = 1, n do r.place_missing[i] = 0; r.place_remaining[i] = 0; r.deviating[i] = 0; r.waiting[i] = {}; r.routes[i] = {} end
    return r
end
function M.fitness(r) return F(1, 2) * (1 - F(r.missing, r.consumed)) + F(1, 2) * (1 - F(r.remaining, r.produced)) end
return M
