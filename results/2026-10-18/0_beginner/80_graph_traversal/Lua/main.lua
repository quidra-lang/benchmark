local adjacency = {}
for vertex = 0, 8 do adjacency[vertex] = {} end
for _, edge in ipairs({{5, 0}, {3, 8}, {7, 2}, {1, 6}, {0, 2}, {5, 3}, {7, 5}, {6, 4}, {8, 7}}) do
    local a, b = table.unpack(edge)
    adjacency[a][#adjacency[a] + 1] = b
    adjacency[b][#adjacency[b] + 1] = a
end
for vertex = 0, 8 do table.sort(adjacency[vertex]) end

local function dfs(vertex, seen, order)
    seen[vertex] = true
    order[#order + 1] = vertex
    for _, neighbor in ipairs(adjacency[vertex]) do
        if not seen[neighbor] then dfs(neighbor, seen, order) end
    end
end

local order = {}
dfs(0, {}, order)
io.write("DFS: ", table.concat(order, " "), "\n")
local queue, seen, head = {0}, {[0] = true}, 1
while head <= #queue do
    local vertex = queue[head]
    head = head + 1
    for _, neighbor in ipairs(adjacency[vertex]) do
        if not seen[neighbor] then
            seen[neighbor] = true
            queue[#queue + 1] = neighbor
        end
    end
end
io.write("BFS: ", table.concat(queue, " "), "\n")
local components = {}
seen = {}
for vertex = 0, 8 do
    if not seen[vertex] then
        local component = {}
        dfs(vertex, seen, component)
        table.sort(component)
        components[#components + 1] = component
    end
end
io.write(string.format("components: %d\n", #components))
for number, component in ipairs(components) do
    io.write(string.format("component %d: %s\n", number, table.concat(component, " ")))
end
