local clocks = require('clocks')
local processes = require('processes')
local M = {}
function M.graph(events, copies, states)
    local result = {}
    for _, event in ipairs(events) do
        local edges = {}
        local following = states[event.process].events[event.local_number + 1]
        if following then edges[#edges + 1] = following.number end
        result[event.number] = edges
    end
    for _, copy in ipairs(copies) do
        if copy.recv_event then
            local edges = result[copy.send_event.number]
            edges[#edges + 1] = copy.recv_event.number
        end
    end
    return result
end
function M.path(first, last, edges)
    local queue, head, parent = {first}, 1, {[first] = 0}
    while head <= #queue and not parent[last] do
        local current = queue[head]
        head = head + 1
        for _, next_number in ipairs(edges[current]) do
            if parent[next_number] == nil then parent[next_number] = current; queue[#queue + 1] = next_number end
        end
    end
    if not parent[last] then return nil end
    local reversed, result, current = {}, {}, last
    while current ~= 0 do reversed[#reversed + 1] = current; current = parent[current] end
    for i = #reversed, 1, -1 do result[#result + 1] = reversed[i] end
    return result
end
function M.concurrency(events, size)
    local result = {pairs = #events * (#events - 1) // 2, ordered = 0, concurrent = 0, same_lamport = 0, inversions = 0, by_pair = {}}
    for i = 1, size do result.by_pair[i] = {}; for j = 1, size do result.by_pair[i][j] = 0 end end
    for i, first in ipairs(events) do
        for j = i + 1, #events do
            local second = events[j]
            if clocks.relation(first.vector, second.vector) == '||' then
                result.concurrent = result.concurrent + 1
                if first.lamport == second.lamport then result.same_lamport = result.same_lamport + 1 end
                local a, b = math.min(first.process, second.process), math.max(first.process, second.process)
                result.by_pair[a][b] = result.by_pair[a][b] + 1
            else result.ordered = result.ordered + 1 end
            if (first.time - second.time) * (first.lamport - second.lamport) < 0 then result.inversions = result.inversions + 1 end
        end
    end
    return result
end
function M.races(states)
    local races, violations, fifo = {}, {}, 0
    for p, state in ipairs(states) do
        local delivered = state.delivered
        for i = 1, #delivered - 1 do
            local first, second = delivered[i], delivered[i + 1]
            if clocks.relation(first.send_event.vector, second.send_event.vector) == '||' then races[#races + 1] = {p, first, second} end
            for j = i + 1, #delivered do
                local later = delivered[j]
                if clocks.before(later.send_event.vector, first.send_event.vector) then
                    violations[#violations + 1] = {p, first, later}
                    if first.source == later.source then fifo = fifo + 1 end
                end
            end
        end
    end
    return races, violations, fifo
end
function M.consistent(cut, states)
    for p, count in ipairs(cut) do
        if count > 0 and not clocks.less_equal(states[p].events[count].vector, cut) then return false end
    end
    return true
end
function M.enumerate(states, limit, thresholds)
    local limits, multipliers, product, level_count, initial = {}, {}, 1, 0, 0
    for p, state in ipairs(states) do
        local count = 0
        for _, event in ipairs(state.events) do if event.time <= limit then count = count + 1 end end
        limits[p], multipliers[p] = count, product
        product, level_count, initial = product * (count + 1), level_count + count, initial + state.initial
    end
    local levels, valid, amounts, counts, consistent = {}, {}, {}, {}, 0
    for i = 0, level_count do levels[i + 1] = 0 end
    for i = 1, #thresholds do counts[i] = 0 end
    for code = 0, product - 1 do
        local cut, level, balance = {}, 0, 0
        for p, state in ipairs(states) do
            cut[p] = (code // multipliers[p]) % (limits[p] + 1)
            level = level + cut[p]
            balance = balance + processes.balance(state, cut[p])
        end
        if M.consistent(cut, states) then
            valid[code], amounts[code] = true, initial - balance
            consistent = consistent + 1
            levels[level + 1] = levels[level + 1] + 1
            for i, threshold in ipairs(thresholds) do if amounts[code] >= threshold then counts[i] = counts[i] + 1 end end
        end
    end
    local predicates = {}
    for i, threshold in ipairs(thresholds) do
        local reachable = {[0] = true}
        local avoids = false
        for code = 0, product - 1 do
            if reachable[code] and valid[code] and amounts[code] < threshold then
                if code == product - 1 then avoids = true end
                for p, count in ipairs(limits) do
                    if (code // multipliers[p]) % (count + 1) < count then
                        local next_code = code + multipliers[p]
                        if valid[next_code] then reachable[next_code] = true end
                    end
                end
            end
        end
        predicates[i] = {cuts = counts[i], possibly = counts[i] > 0, definitely = not avoids}
    end
    return {limits = limits, product = product, consistent = consistent, levels = levels, predicates = predicates}
end
return M
