local M = {}

function M.strong(adjacency)
    local order, low, on_stack, stack, groups, counter = {}, {}, {}, {}, {}, 0
    for i = 1, #adjacency do order[i], low[i], on_stack[i] = -1, 0, false end
    for root = 1, #adjacency do if order[root] == -1 then
        order[root], low[root], counter = counter, counter, counter + 1
        stack[#stack + 1], on_stack[root] = root, true
        local work = {{root, 1}}
        while #work > 0 do
            local frame = work[#work]
            local node, position = frame[1], frame[2]
            if position <= #adjacency[node] then
                frame[2] = position + 1
                local child = adjacency[node][position]
                if order[child] == -1 then
                    order[child], low[child], counter = counter, counter, counter + 1
                    stack[#stack + 1], on_stack[child] = child, true
                    work[#work + 1] = {child, 1}
                elseif on_stack[child] then low[node] = math.min(low[node], order[child]) end
            else
                table.remove(work)
                if #work > 0 then local parent = work[#work][1]; low[parent] = math.min(low[parent], low[node]) end
                if low[node] == order[node] then
                    local group = {}
                    while true do
                        local member = table.remove(stack)
                        on_stack[member] = false
                        group[#group + 1] = member
                        if member == node then break end
                    end
                    groups[#groups + 1] = group
                end
            end
        end
    end end
    return groups
end

function M.reachable(adjacency, starts)
    local seen, stack = {}, {}
    for i = 1, #adjacency do seen[i] = false end
    for _, node in ipairs(starts) do if not seen[node] then seen[node] = true; stack[#stack + 1] = node end end
    while #stack > 0 do
        local node = table.remove(stack)
        for _, neighbor in ipairs(adjacency[node]) do if not seen[neighbor] then seen[neighbor] = true; stack[#stack + 1] = neighbor end end
    end
    return seen
end

function M.bfs(adjacency, starts)
    local distance, queue, head = {}, {}, 1
    for i = 1, #adjacency do distance[i] = -1 end
    for _, node in ipairs(starts) do if distance[node] == -1 then distance[node] = 0; queue[#queue + 1] = node end end
    while head <= #queue do
        local node = queue[head]; head = head + 1
        for _, neighbor in ipairs(adjacency[node]) do if distance[neighbor] == -1 then distance[neighbor] = distance[node] + 1; queue[#queue + 1] = neighbor end end
    end
    return distance
end

function M.weak(neighbors)
    local labels, count = {}, 0
    for i = 1, #neighbors do labels[i] = -1 end
    for start = 1, #neighbors do if labels[start] == -1 then
        count = count + 1
        labels[start] = count
        local stack = {start}
        while #stack > 0 do
            local node = table.remove(stack)
            for _, neighbor in ipairs(neighbors[node]) do if labels[neighbor] == -1 then labels[neighbor] = count; stack[#stack + 1] = neighbor end end
        end
    end end
    return labels
end

return M
