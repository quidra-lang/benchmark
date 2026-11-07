local Molecule = require("molecule")
local Parser = require("smiles_parser")
local Search = {}

local function atom_key(symbol, aromatic)
    return symbol .. ":" .. (aromatic and "1" or "0")
end

function Search.read_atom(text, position)
    local character = text:sub(position, position)
    if character == "*" then return {}, position + 1 end
    if character == "A" or character == "a" then return {aromatic = character == "a"}, position + 1 end
    if character == "[" then
        local close = text:find("]", position + 1, true)
        if not close then Molecule.fail("unclosed bracket", position) end
        local choices = {}
        for item in (text:sub(position + 1, close - 1) .. ","):gmatch("(.-),") do
            local symbol, aromatic, next_position = Parser.organic(item, 1)
            if not symbol or next_position ~= #item + 1 then Molecule.fail("bad bracket atom", position) end
            choices[atom_key(symbol, aromatic)] = true
        end
        return {choices = choices}, close + 1
    end
    local symbol, aromatic, next_position = Parser.organic(text, position)
    if not symbol then Molecule.fail("unexpected character", position) end
    return {choices = {[atom_key(symbol, aromatic)] = true}}, next_position
end

function Search.molecule_pattern(molecule)
    local pattern = Molecule.new(molecule.elements)
    for _, atom in ipairs(molecule.atoms) do pattern:add_atom({choices = {[atom_key(atom.element.symbol, atom.aromatic)] = true}}) end
    for _, bond in ipairs(molecule:ordered_bonds()) do pattern:add_bond(bond.first, bond.second, bond.kind) end
    return pattern
end

local function atom_matches(pattern, atom)
    if pattern.choices then return pattern.choices[atom_key(atom.element.symbol, atom.aromatic)] == true end
    return pattern.aromatic == nil or pattern.aromatic == atom.aromatic
end

local function bond_matches(pattern, bond)
    local symbol = pattern.symbol
    if symbol == nil then return bond.kind == 1 or bond.kind == 4 end
    if symbol == "~" then return true end
    return bond.kind == (type(symbol) == "number" and symbol or Molecule.bond_types[symbol])
end

function Search.embeddings(pattern, molecule)
    if #pattern.atoms > #molecule.atoms then return 0, 0, nil end
    local candidates, earlier = {}, {}
    for i, atom in ipairs(pattern.atoms) do
        local choices, edges = {}, {}
        for number, target in ipairs(molecule.atoms) do
            if atom_matches(atom, target) and #molecule.adjacency[number] >= #pattern.adjacency[i] then choices[#choices + 1] = number end
        end
        for _, neighbor in ipairs(pattern.adjacency[i]) do
            if neighbor < i then edges[#edges + 1] = {neighbor, pattern.neighbors[i][neighbor]} end
        end
        candidates[i], earlier[i] = choices, edges
    end
    local mapping, used, unique, count, unique_count, first_mapping = {}, {}, {}, 0, 0, nil
    local function assign(index)
        if index > #pattern.atoms then
            count = count + 1
            local atoms = {}
            for atom in pairs(used) do atoms[#atoms + 1] = atom end
            table.sort(atoms)
            local key = table.concat(atoms, ",")
            if not unique[key] then unique[key], unique_count = true, unique_count + 1 end
            if not first_mapping then
                first_mapping = {}
                for i, atom in ipairs(mapping) do first_mapping[i] = atom end
            end
            return
        end
        for _, atom in ipairs(candidates[index]) do
            if not used[atom] then
                local valid = true
                for _, edge in ipairs(earlier[index]) do
                    local target = molecule.neighbors[atom][mapping[edge[1]]]
                    if not target or not bond_matches(edge[2], target) then valid = false; break end
                end
                if valid then
                    mapping[index], used[atom] = atom, true
                    assign(index + 1)
                    mapping[index], used[atom] = nil, nil
                end
            end
        end
    end
    assign(1)
    return count, unique_count, first_mapping
end

function Search.fingerprint(molecule)
    local codes, bits, count, used = {}, {}, 0, {}
    for i, atom in ipairs(molecule.atoms) do codes[i] = 16 * atom.element.number + (atom.aromatic and 8 or 0) + #molecule.adjacency[i] end
    local function extend(atom, depth, value)
        count, bits[value % 1024] = count + 1, true
        if depth == 5 then return end
        for _, neighbor in ipairs(molecule.adjacency[atom]) do
            if not used[neighbor] then
                local next_value = (value * 31 + molecule.neighbors[atom][neighbor].kind) % 1000003
                next_value = (next_value * 31 + codes[neighbor]) % 1000003
                used[neighbor] = true
                extend(neighbor, depth + 1, next_value)
                used[neighbor] = nil
            end
        end
    end
    for i, code in ipairs(codes) do used[i] = true; extend(i, 0, code); used[i] = nil end
    return bits, count
end

function Search.tanimoto(first, second)
    local common, union = 0, 0
    for bit in pairs(first) do if second[bit] then common = common + 1 end; union = union + 1 end
    for bit in pairs(second) do if not first[bit] then union = union + 1 end end
    return {common, union}
end

return Search
