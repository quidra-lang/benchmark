local Molecule = require("molecule")
local Canonical = {}

local function compare(a, b)
    if type(a) == "number" then return a < b and -1 or a > b and 1 or 0 end
    for i = 1, math.min(#a, #b) do local difference = compare(a[i], b[i]); if difference ~= 0 then return difference end end
    return #a < #b and -1 or #a > #b and 1 or 0
end

function Canonical.dense(values)
    local order, ranks, rank = {}, {}, 0
    for i = 1, #values do order[i] = i end
    table.sort(order, function(a, b) return compare(values[a], values[b]) < 0 end)
    local previous
    for _, i in ipairs(order) do
        if previous == nil or compare(values[i], previous) ~= 0 then rank = rank + 1; previous = values[i] end
        ranks[i] = rank
    end
    return ranks, rank
end

local function distinct(ranks)
    local maximum = 0
    for _, rank in ipairs(ranks) do maximum = math.max(maximum, rank) end
    return maximum
end

local function refine(molecule, ranks)
    while true do
        local values = {}
        for atom = 1, #molecule.atoms do
            local neighbors = {}
            for _, neighbor in ipairs(molecule.adjacency[atom]) do neighbors[#neighbors + 1] = {ranks[neighbor], molecule.neighbors[atom][neighbor].kind} end
            table.sort(neighbors, function(a, b) return compare(a, b) < 0 end)
            values[atom] = {ranks[atom], neighbors}
        end
        local refined, count = Canonical.dense(values)
        if count == distinct(ranks) then return refined end
        ranks = refined
    end
end

function Canonical.ranks(molecule)
    local values = {}
    for i, atom in ipairs(molecule.atoms) do values[i] = {#molecule.adjacency[i], atom.element.number, atom.mass,
        atom.charge, atom.hydrogens, atom.aromatic and 1 or 0} end
    local initial = Canonical.dense(values)
    local ranks = refine(molecule, initial)
    local classes = distinct(ranks)
    while distinct(ranks) ~= #ranks do
        local counts, tied = {}, nil
        for _, rank in ipairs(ranks) do counts[rank] = (counts[rank] or 0) + 1 end
        for rank = 1, #ranks do if (counts[rank] or 0) > 1 then tied = rank; break end end
        local first
        for i, rank in ipairs(ranks) do if rank == tied then first = i; break end end
        values = {}
        for i, rank in ipairs(ranks) do values[i] = 2 * rank - (i == first and 1 or 0) end
        initial = Canonical.dense(values)
        ranks = refine(molecule, initial)
    end
    return ranks, classes
end

local function atom_notation(molecule, number)
    local atom = molecule.atoms[number]
    local symbol = atom.element.symbol
    local ordinary = Molecule.organic[symbol] and (not atom.aromatic or Molecule.aromatic[symbol]) and atom.mass == 0 and atom.charge == 0
    if atom.aromatic then
        ordinary = ordinary and Molecule.needs_pi(molecule, number) == Molecule.needs_pi(molecule, number, 0)
        symbol = symbol:lower()
    end
    local hydrogens = Molecule.organic_hydrogens(atom, molecule:bond_total(number))
    if ordinary and hydrogens ~= nil and hydrogens == atom.hydrogens then return symbol end
    local text = "[" .. (atom.mass ~= 0 and tostring(atom.mass) or "") .. symbol
    if atom.hydrogens > 0 then text = text .. "H" .. (atom.hydrogens == 1 and "" or tostring(atom.hydrogens)) end
    if atom.charge ~= 0 then
        text = text .. (atom.charge > 0 and "+" or "-")
        if math.abs(atom.charge) ~= 1 then text = text .. math.abs(atom.charge) end
    end
    return text .. "]"
end

local function bond_symbol(molecule, bond)
    local in_ring = bond.ring and molecule.atoms[bond.first].aromatic and molecule.atoms[bond.second].aromatic
    if bond.kind == 1 then return in_ring and "-" or "" end
    if bond.kind == 2 then return "=" end
    if bond.kind == 3 then return "#" end
    return in_ring and "" or ":"
end

function Canonical.smiles(molecule, ranks)
    local visits, children, closures, visit_count = {}, {}, {}, 0
    for i = 1, #molecule.atoms do children[i] = {} end
    local function visit(atom, incoming)
        visit_count = visit_count + 1
        visits[atom] = visit_count
        local neighbors = {}
        for i, neighbor in ipairs(molecule.adjacency[atom]) do neighbors[i] = neighbor end
        table.sort(neighbors, function(a, b) return ranks[a] < ranks[b] end)
        for _, neighbor in ipairs(neighbors) do
            local bond = molecule.neighbors[atom][neighbor]
            if bond ~= incoming and not closures[bond] then
                if not visits[neighbor] then
                    children[atom][#children[atom] + 1] = {neighbor, bond}
                    visit(neighbor, bond)
                else closures[bond] = true end
            end
        end
    end
    local root
    for i, rank in ipairs(ranks) do if rank == 1 then root = i; break end end
    visit(root, nil)
    local assignments, occupied = {}, {}
    local function write(atom)
        local parts, neighbors = {atom_notation(molecule, atom)}, {}
        for i, neighbor in ipairs(molecule.adjacency[atom]) do neighbors[i] = neighbor end
        table.sort(neighbors, function(a, b) return visits[a] < visits[b] end)
        for _, neighbor in ipairs(neighbors) do
            local bond = molecule.neighbors[atom][neighbor]
            if closures[bond] then
                local number, symbol = assignments[bond], ""
                if number then assignments[bond], occupied[number] = nil, nil
                else
                    number = 1
                    while occupied[number] do number = number + 1 end
                    assignments[bond], occupied[number], symbol = number, true, bond_symbol(molecule, bond)
                end
                parts[#parts + 1] = symbol .. (number < 10 and tostring(number) or string.format("%%%02d", number))
            end
        end
        for index, child in ipairs(children[atom]) do
            local continuation = bond_symbol(molecule, child[2]) .. write(child[1])
            parts[#parts + 1] = index < #children[atom] and "(" .. continuation .. ")" or continuation
        end
        return table.concat(parts)
    end
    return write(root)
end

function Canonical.canonicalize(molecule)
    local ranks, classes = Canonical.ranks(molecule)
    return Canonical.smiles(molecule, ranks), classes
end

return Canonical
