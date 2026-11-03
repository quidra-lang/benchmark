local M = {}
local function action(tokens, first, indices)
    local kind = tokens[first]
    if kind == 'LOCAL' or kind == 'BROADCAST' or kind == 'SNAPSHOT' then return {kind = kind, value = tokens[first + 1]} end
    return {kind = kind, destination = tokens[first + 1] == 'SENDER' and 0 or indices[tokens[first + 1]],
        value = kind == 'TRANSFER' and tonumber(tokens[first + 2]) or tokens[first + 2]}
end
function M.read(indices)
    local input = assert(io.open('input/programs.txt', 'r'))
    local blocks, current = {}, nil
    for line in input:lines() do
        local t = {}
        for word in line:gmatch('%S+') do t[#t + 1] = word end
        if t[1] == 'PROCESS' then
            current = {initial = tonumber(t[4]), at = {}, on = {}}
            blocks[indices[t[2]]] = current
        elseif t[1] == 'AT' then
            local recurring = t[3] == 'EVERY'
            current.at[#current.at + 1] = {start = tonumber(t[2]), period = recurring and tonumber(t[4]) or nil, action = action(t, recurring and 5 or 3, indices)}
        elseif t[1] == 'ON' then current.on[#current.on + 1] = {tag = t[2], action = action(t, 3, indices)} end
    end
    input:close()
    return blocks
end
function M.initialize(blocks, size)
    local result = {}
    for p = 1, size do
        local b = blocks[p]
        local state = {initial = b.initial, balance = b.initial, lamport = 0, vector = {}, broadcast = {}, at = b.at, on = b.on,
            events = {}, next_sequence = {}, reorder = {}, holdback = {}, delivered = {}, max_held = 0,
            received = 0, sent = 0, refused = 0, minimum = b.initial, counts = {}}
        for q = 1, size do
            state.vector[q], state.broadcast[q], state.next_sequence[q], state.reorder[q] = 0, 0, 1, {}
        end
        result[p] = state
    end
    return result
end
function M.schedule(states, limit, enqueue)
    for p, state in ipairs(states) do
        for _, entry in ipairs(state.at) do
            local now = entry.start
            while now <= limit do
                enqueue(now, p, false, entry.action)
                if not entry.period then break end
                now = now + entry.period
            end
        end
    end
end
function M.balance(state, count)
    return count == 0 and state.initial or state.events[count].balance
end
function M.held(state)
    local result = #state.holdback
    for _, buffer in ipairs(state.reorder) do for _ in pairs(buffer) do result = result + 1 end end
    return result
end
return M
