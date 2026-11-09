local topology = require("topology")
local M = {}
function M.has_directed(vertices, a, b)
    for _, edge in ipairs(topology.directed(vertices)) do
        if edge[1] == a and edge[2] == b then
            return true
        end
    end
    return false
end
function M.flip(face)
    face.vertices[2], face.vertices[3] = face.vertices[3], face.vertices[2]
end
function M.inconsistent(faces, edges)
    local result = {}
    for _, edge in ipairs(edges) do
        if #edge.faces == 2 and M.has_directed(faces[edge.faces[1]].vertices, edge.a, edge.b) == M.has_directed(faces[edge.faces[2]].vertices, edge.a, edge.b) then
            result[#result + 1] = edge
        end
    end
    return result
end
function M.repair(faces, mesh)
    local visited = {}
    for seed = 1, #faces do
        if not visited[seed] then
            local queue, head = {seed}, 1
            visited[seed] = true
            while head <= #queue do
                local current = queue[head]
                head = head + 1
                for _, pair in ipairs(topology.directed(faces[current].vertices)) do
                    local edge = mesh.by_key[topology.key(pair[1], pair[2])]
                    if #edge.faces == 2 then
                        local other = edge.faces[1] == current and edge.faces[2] or edge.faces[1]
                        if not visited[other] then
                            if M.has_directed(faces[other].vertices, pair[1], pair[2]) then
                                M.flip(faces[other])
                            end
                            visited[other], queue[#queue + 1] = true, other
                        end
                    end
                end
            end
        end
    end
end
return M
