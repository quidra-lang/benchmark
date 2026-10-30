local Molecule = require("molecule")
local Aromatic = {}

local function lex_less(a, b)
    for i = 1, math.min(#a, #b) do if a[i] ~= b[i] then return a[i] < b[i] end end
    return #a < #b
end

local function breadth_first(molecule, root)
    local parents, paths, queue, head = {[root] = false}, {}, {root}, 1
    while head <= #queue do
        local atom = queue[head]
        head = head + 1
        for _, neighbor in ipairs(molecule.adjacency[atom]) do
            if parents[neighbor] == nil then parents[neighbor] = atom; queue[#queue + 1] = neighbor end
        end
    end
    for atom = 1, #molecule.atoms do
        local path, current = {}, atom
        while current do path[#path + 1] = current; current = parents[current] end
        paths[atom] = path
    end
    return parents, paths
end

local function ring_edges(molecule, sequence)
    local edges, ids = {}, {}
    for i, atom in ipairs(sequence) do
        local other = sequence[(i - 2) % #sequence + 1]
        local id = molecule.neighbors[atom][other].order
        edges[id], ids[#ids + 1] = true, id
    end
    table.sort(ids)
    return edges, table.concat(ids, ",")
end

local function normalized(sequence)
    local first, result = 1, {}
    for i = 2, #sequence do if sequence[i] < sequence[first] then first = i end end
    for i = 0, #sequence - 1 do result[i + 1] = sequence[(first + i - 1) % #sequence + 1] end
    if result[2] > result[#result] then
        local reverse = {result[1]}
        for i = #result, 2, -1 do reverse[#reverse + 1] = result[i] end
        return reverse
    end
    return result
end

function Aromatic.find_rings(molecule)
    local bonds, candidates, seen = molecule:ordered_bonds(), {}, {}
    for root = 1, #molecule.atoms do
        local parents, paths = breadth_first(molecule, root)
        for _, bond in ipairs(bonds) do
            local first, second = bond.first, bond.second
            if parents[first] ~= second and parents[second] ~= first then
                local ancestors, shared = {}, 0
                for _, atom in ipairs(paths[first]) do ancestors[atom] = true end
                for _, atom in ipairs(paths[second]) do if ancestors[atom] then shared = shared + 1 end end
                if shared == 1 then
                    local sequence = {}
                    for i = #paths[first], 1, -1 do sequence[#sequence + 1] = paths[first][i] end
                    for i = 1, #paths[second] - 1 do sequence[#sequence + 1] = paths[second][i] end
                    local edges, key = ring_edges(molecule, sequence)
                    if not seen[key] then
                        seen[key] = true
                        candidates[#candidates + 1] = {sequence = sequence, edges = edges, number = #candidates + 1}
                    end
                end
            end
        end
    end
    table.sort(candidates, function(a, b)
        if #a.sequence ~= #b.sequence then return #a.sequence < #b.sequence end
        return a.number < b.number
    end)
    local basis, rings = {}, {}
    for _, candidate in ipairs(candidates) do
        local reduced = {}
        for id in pairs(candidate.edges) do reduced[id] = true end
        while next(reduced) do
            local pivot = 0
            for id in pairs(reduced) do pivot = math.max(pivot, id) end
            if not basis[pivot] then basis[pivot] = reduced; rings[#rings + 1] = normalized(candidate.sequence); break end
            for id in pairs(basis[pivot]) do reduced[id] = not reduced[id] or nil end
        end
    end
    table.sort(rings, function(a, b)
        if #a ~= #b then return #a < #b end
        return lex_less(a, b)
    end)
    molecule.rings = rings
    for _, ring in ipairs(rings) do
        for _, atom in ipairs(ring) do molecule.ring_atoms[atom] = true end
        for id in pairs(ring_edges(molecule, ring)) do bonds[id].ring = true end
    end
end

function Aromatic.kekulize(molecule, needing)
    local remaining, selected = {}, {}
    for _, atom in ipairs(needing) do remaining[atom] = true end
    for start = 1, #molecule.atoms do
        if remaining[start] then
            local system, queue, head = {[start] = true}, {start}, 1
            remaining[start] = nil
            while head <= #queue do
                local atom = queue[head]
                head = head + 1
                for _, neighbor in ipairs(molecule.adjacency[atom]) do
                    if molecule.neighbors[atom][neighbor].kind == 4 and remaining[neighbor] then
                        remaining[neighbor], system[neighbor] = nil, true
                        queue[#queue + 1] = neighbor
                    end
                end
            end
            local unpaired, matching = {}, {}
            for atom in pairs(system) do unpaired[atom] = true end
            local function search()
                local first
                for atom = 1, #molecule.atoms do if unpaired[atom] then first = atom; break end end
                if not first then return true end
                unpaired[first] = nil
                for _, second in ipairs(molecule.adjacency[first]) do
                    local bond = molecule.neighbors[first][second]
                    if unpaired[second] and bond.kind == 4 then
                        unpaired[second] = nil
                        matching[#matching + 1] = bond
                        if search() then return true end
                        matching[#matching], unpaired[second] = nil, true
                    end
                end
                unpaired[first] = true
                return false
            end
            if not search() then Molecule.fail("kekulization failed", molecule.atoms[start].column) end
            for _, bond in ipairs(matching) do selected[bond] = true end
        end
    end
    for _, bond in ipairs(molecule.bonds) do bond.multiplicity = bond.kind == 4 and (selected[bond] and 2 or 1) or bond.kind end
end

return Aromatic
