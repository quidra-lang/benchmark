local M = {}

function M.run(count, nodes, links, iterations)
    local sources, targets, authority, hub = {}, {}, {}, {}
    for i = 1, count do sources[i], targets[i], authority[i], hub[i] = {}, {}, 0.0, 0.0 end
    local ordered = {}; for i, edge in ipairs(links) do ordered[i] = edge end
    table.sort(ordered, function(a, b) return a[1] < b[1] or a[1] == b[1] and a[2] < b[2] end)
    for _, edge in ipairs(ordered) do table.insert(sources[edge[2]], edge[1]); table.insert(targets[edge[1]], edge[2]) end
    for _, node in ipairs(nodes) do authority[node], hub[node] = 1.0, 1.0 end
    for step = 1, iterations do
        local incoming, outgoing, anorm, hnorm = {}, {}, 0.0, 0.0
        for i = 1, count do incoming[i], outgoing[i] = 0.0, 0.0 end
        for _, node in ipairs(nodes) do for _, source in ipairs(sources[node]) do incoming[node] = incoming[node] + hub[source] end end
        for _, node in ipairs(nodes) do for _, target in ipairs(targets[node]) do outgoing[node] = outgoing[node] + incoming[target] end end
        for _, node in ipairs(nodes) do anorm = anorm + incoming[node] * incoming[node]; hnorm = hnorm + outgoing[node] * outgoing[node] end
        anorm, hnorm = math.sqrt(anorm), math.sqrt(hnorm)
        for _, node in ipairs(nodes) do authority[node], hub[node] = incoming[node] / anorm, outgoing[node] / hnorm end
    end
    return authority, hub
end

return M
