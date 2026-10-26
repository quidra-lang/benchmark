local names = "ABCDEFG"
local weights = {}
for i = 1, 7 do weights[i] = {} end
local edges = {
    {"A", "B", 7}, {"A", "C", 3}, {"A", "D", 9}, {"B", "C", 2}, {"C", "E", 6}, {"B", "D", 3},
    {"D", "E", 4}, {"D", "F", 5}, {"E", "F", 3}, {"E", "G", 8}, {"F", "G", 4},
}
for _, edge in ipairs(edges) do
    local i, j = edge[1]:byte() - 64, edge[2]:byte() - 64
    weights[i][j], weights[j][i] = edge[3], edge[3]
end
local distance, previous, finalized = {}, {}, {}
for i = 1, 7 do distance[i] = math.huge end
distance[1] = 0
for _ = 1, 7 do
    local vertex
    for i = 1, 7 do
        if not finalized[i] and (not vertex or distance[i] < distance[vertex]) then vertex = i end
    end
    finalized[vertex] = true
    for neighbor = 1, 7 do
        local weight = weights[vertex][neighbor]
        if weight and distance[vertex] + weight < distance[neighbor] then
            distance[neighbor] = distance[vertex] + weight
            previous[neighbor] = vertex
        end
    end
end
for i = 1, 7 do
    local path, vertex = {}, i
    while vertex do
        table.insert(path, 1, names:sub(vertex, vertex))
        vertex = previous[vertex]
    end
    io.write(string.format("%s: distance=%d path=%s\n", names:sub(i, i), distance[i], table.concat(path, "-")))
end
