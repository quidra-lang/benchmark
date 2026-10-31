local Layering = {}

function Layering.neighbors(count, edges)
    local upper, lower = {}, {}
    for i = 1, count do upper[i], lower[i] = {}, {} end
    for _, edge in ipairs(edges) do
        local first, second = edge[1], edge[2]
        upper[second][#upper[second] + 1], lower[first][#lower[first] + 1] = first, second
    end
    return upper, lower
end

function Layering.acyclic_order(count, edges)
    local upper, lower = Layering.neighbors(count, edges)
    local remaining, head, tail = {}, {}, {}
    for i = 1, count do remaining[i] = true end
    for _ = 1, count do
        local indegree, outdegree, sink, source, chosen, best = {}, {}, nil, nil, nil, nil
        for v = 1, count do
            if remaining[v] then
                local incoming, outgoing = 0, 0
                for _, u in ipairs(upper[v]) do if remaining[u] then incoming = incoming + 1 end end
                for _, w in ipairs(lower[v]) do if remaining[w] then outgoing = outgoing + 1 end end
                indegree[v], outdegree[v] = incoming, outgoing
                if outgoing == 0 and not sink then sink = v end
                if incoming == 0 and not source then source = v end
                if not best or outgoing - incoming > best then chosen, best = v, outgoing - incoming end
            end
        end
        if sink then chosen = sink; table.insert(tail, 1, chosen)
        else chosen = source or chosen; head[#head + 1] = chosen end
        remaining[chosen] = nil
    end
    for _, vertex in ipairs(tail) do head[#head + 1] = vertex end
    return head
end

local function lex_less(a, b)
    for i = 1, math.min(#a, #b) do if a[i] ~= b[i] then return a[i] < b[i] end end
    return #a < #b
end

function Layering.assign(count, edges, settings)
    local upper, lower = Layering.neighbors(count, edges)
    local heights, labels = {}, nil
    if settings.layering == "coffman" then
        labels = {}
        for label = 1, count do
            local chosen, best
            for v = 1, count do
                if not labels[v] then
                    local sequence, ready = {}, true
                    for _, u in ipairs(upper[v]) do if not labels[u] then ready = false; break end; sequence[#sequence + 1] = labels[u] end
                    if ready then
                        table.sort(sequence, function(a, b) return a > b end)
                        if not chosen or lex_less(sequence, best) then chosen, best = v, sequence end
                    end
                end
            end
            labels[chosen] = label
        end
        local current, occupied = 0, 0
        for _ = 1, count do
            local chosen
            for v = 1, count do
                if heights[v] == nil then
                    local ready = true
                    for _, w in ipairs(lower[v]) do if heights[w] == nil then ready = false; break end end
                    if ready and (not chosen or labels[v] > labels[chosen]) then chosen = v end
                end
            end
            local same_height = false
            for _, w in ipairs(lower[chosen]) do if heights[w] == current then same_height = true end end
            if occupied == settings.width or same_height then current, occupied = current + 1, 0 end
            heights[chosen], occupied = current, occupied + 1
        end
    else
        for _ = 1, count do
            for v = 1, count do
                if heights[v] == nil then
                    local ready, height = true, 0
                    for _, w in ipairs(lower[v]) do
                        if heights[w] == nil then ready = false; break end
                        height = math.max(height, heights[w] + 1)
                    end
                    if ready then heights[v] = height; break end
                end
            end
        end
    end
    local dummies_before, rounds, record = 0, 0, {}
    for _, edge in ipairs(edges) do dummies_before = dummies_before + heights[edge[1]] - heights[edge[2]] - 1 end
    local function promote(vertex)
        local difference = 0
        for _, predecessor in ipairs(upper[vertex]) do
            if heights[predecessor] == heights[vertex] + 1 then difference = difference + promote(predecessor) end
        end
        heights[vertex] = heights[vertex] + 1
        return difference + #lower[vertex] - #upper[vertex]
    end
    if settings.promotion == "on" then
        while true do
            rounds = rounds + 1
            local accepted = 0
            for v = 1, count do
                if #upper[v] > 0 then
                    local saved = {}
                    for i, height in ipairs(heights) do saved[i] = height end
                    local difference = promote(v)
                    if difference < 0 then record[#record + 1] = {rounds, v, difference}; accepted = accepted + 1 else heights = saved end
                end
            end
            if accepted == 0 then break end
        end
    end
    return heights, labels, dummies_before, rounds, record
end

return Layering
