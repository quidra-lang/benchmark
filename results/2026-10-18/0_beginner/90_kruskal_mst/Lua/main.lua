local edges = {
    {"A", "B", 7}, {"C", "A", 4}, {"B", "C", 9}, {"B", "D", 14}, {"D", "C", 6}, {"C", "E", 3},
    {"E", "D", 5}, {"F", "D", 11}, {"E", "G", 16}, {"G", "F", 8}, {"H", "F", 12}, {"G", "H", 2},
    {"H", "E", 10},
}
table.sort(edges, function(a, b) return a[3] < b[3] end)
local parents = {}
for vertex in ("ABCDEFGH"):gmatch(".") do parents[vertex] = vertex end

local function root(vertex)
    while parents[vertex] ~= vertex do
        parents[vertex] = parents[parents[vertex]]
        vertex = parents[vertex]
    end
    return vertex
end

local accepted, skipped, total = 0, 0, 0
for _, edge in ipairs(edges) do
    local a, b, weight = table.unpack(edge)
    local first, second = root(a), root(b)
    if first == second then
        skipped = skipped + 1
    else
        parents[second] = first
        accepted, total = accepted + 1, total + weight
        if a > b then a, b = b, a end
        io.write(string.format("%s-%s %d\n", a, b, weight))
        if accepted == 7 then break end
    end
end
io.write(string.format("total weight: %d\nskipped: %d\n", total, skipped))
