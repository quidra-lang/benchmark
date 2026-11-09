local M = {}
function M.key(a, b)
    return math.min(a, b) .. "," .. math.max(a, b)
end
function M.directed(vertices)
    return {{vertices[1], vertices[2]}, {vertices[2], vertices[3]}, {vertices[3], vertices[1]}}
end
local function sorted_keys(values)
    local result = {}
    for value in pairs(values) do
        result[#result + 1] = value
    end
    table.sort(result)
    return result
end
local function connected(selected, neighbors)
    local visited, parts = {}, {}
    for _, seed in ipairs(selected) do
        if not visited[seed] then
            local queue, head, part = {seed}, 1, {}
            visited[seed] = true
            while head <= #queue do
                local current = queue[head]
                head = head + 1
                part[#part + 1] = current
                for _, other in ipairs(sorted_keys(neighbors[current] or {})) do
                    if not visited[other] then
                        visited[other], queue[#queue + 1] = true, other
                    end
                end
            end
            table.sort(part)
            parts[#parts + 1] = part
        end
    end
    return parts
end
function M.analyze(faces)
    local mesh = {edges = {}, by_key = {}, components = {}, face_components = {}, fans = {}, nonmanifold_vertices = {}, used = {}}
    local neighbors, all, used = {}, {}, {}
    for id, face in ipairs(faces) do
        neighbors[id], all[id] = {}, id
        for _, v in ipairs(face.vertices) do
            used[v] = true
        end
        for _, pair in ipairs(M.directed(face.vertices)) do
            local key = M.key(pair[1], pair[2])
            local edge = mesh.by_key[key]
            if not edge then
                edge = {a = math.min(pair[1], pair[2]), b = math.max(pair[1], pair[2]), faces = {}}
                mesh.by_key[key] = edge
                mesh.edges[#mesh.edges + 1] = edge
            end
            edge.faces[#edge.faces + 1] = id
        end
    end
    table.sort(mesh.edges, function(a, b) return a.a < b.a or (a.a == b.a and a.b < b.b) end)
    for _, edge in ipairs(mesh.edges) do
        for _, first in ipairs(edge.faces) do
            for _, second in ipairs(edge.faces) do
                if first ~= second then
                    neighbors[first][second] = true
                end
            end
        end
    end
    for number, ids in ipairs(connected(all, neighbors)) do
        local component = {number = number, faces = ids, vertices = {}, edges = {}, boundary = {}, nonmanifold = {}, nonmanifold_vertices = {}}
        local vertices = {}
        for _, id in ipairs(ids) do
            mesh.face_components[id] = number
            for _, vertex in ipairs(faces[id].vertices) do
                vertices[vertex] = true
            end
        end
        component.vertices = sorted_keys(vertices)
        mesh.components[#mesh.components + 1] = component
    end
    for _, edge in ipairs(mesh.edges) do
        local component = mesh.components[mesh.face_components[edge.faces[1]]]
        component.edges[#component.edges + 1] = edge
        if #edge.faces == 1 then
            component.boundary[#component.boundary + 1] = edge
        elseif #edge.faces >= 3 then
            component.nonmanifold[#component.nonmanifold + 1] = edge
        end
    end
    mesh.used = sorted_keys(used)
    for _, vertex in ipairs(mesh.used) do
        local containing, local_neighbors = {}, {}
        for id, face in ipairs(faces) do
            if face.vertices[1] == vertex or face.vertices[2] == vertex or face.vertices[3] == vertex then
                containing[#containing + 1], local_neighbors[id] = id, {}
            end
        end
        for _, edge in ipairs(mesh.edges) do
            if edge.a == vertex or edge.b == vertex then
                for _, first in ipairs(edge.faces) do
                    for _, second in ipairs(edge.faces) do
                        if first ~= second then
                            local_neighbors[first][second] = true
                        end
                    end
                end
            end
        end
        local fans = connected(containing, local_neighbors)
        mesh.fans[vertex] = fans
        if #fans >= 2 then
            mesh.nonmanifold_vertices[#mesh.nonmanifold_vertices + 1] = vertex
        end
        local counts = {}
        for _, fan in ipairs(fans) do
            local number = mesh.face_components[fan[1]]
            counts[number] = (counts[number] or 0) + 1
        end
        for number, count in pairs(counts) do
            if count >= 2 then
                local component = mesh.components[number]
                component.nonmanifold_vertices[#component.nonmanifold_vertices + 1] = vertex
            end
        end
    end
    return mesh
end
function M.loops(faces, mesh)
    local loops = {}
    for _, component in ipairs(mesh.components) do
        local unused = {}
        for _, edge in ipairs(component.boundary) do
            unused[M.key(edge.a, edge.b)] = true
        end
        for _, first in ipairs(component.boundary) do
            local key = M.key(first.a, first.b)
            if unused[key] then
                unused[key] = nil
                local sequence, current = {first.a, first.b}, first.b
                while current ~= first.a do
                    local chosen, other
                    for _, edge in ipairs(component.boundary) do
                        local next_vertex = edge.a == current and edge.b or edge.b == current and edge.a or nil
                        if next_vertex and unused[M.key(edge.a, edge.b)] and (not other or next_vertex < other) then
                            chosen, other = edge, next_vertex
                        end
                    end
                    if not chosen then
                        break
                    end
                    unused[M.key(chosen.a, chosen.b)] = nil
                    sequence[#sequence + 1], current = other, other
                end
                local closed, kind, length = current == first.a, "open", #sequence - 1
                if closed then
                    table.remove(sequence)
                    local forward = 0
                    for index, a in ipairs(sequence) do
                        local b = sequence[index % #sequence + 1]
                        local edge = mesh.by_key[M.key(a, b)]
                        local vertices = faces[edge.faces[1]].vertices
                        for _, pair in ipairs(M.directed(vertices)) do
                            if pair[1] == a and pair[2] == b then
                                forward = forward + 1
                            end
                        end
                    end
                    kind = forward == #sequence and "coherent" or "mixed"
                    if forward == 0 then
                        kind = "coherent"
                        local reversed = {sequence[1]}
                        for index = #sequence, 2, -1 do
                            reversed[#reversed + 1] = sequence[index]
                        end
                        sequence = reversed
                    end
                end
                loops[#loops + 1] = {number = #loops + 1, component = component.number, vertices = sequence, length = length, kind = kind, filled = false}
            end
        end
    end
    return loops
end
return M
