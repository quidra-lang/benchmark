local Molecule = {}
Molecule.__index = Molecule
Molecule.organic = {B = true, C = true, N = true, O = true, P = true, S = true, F = true, Cl = true, Br = true, I = true}
Molecule.aromatic = {B = true, C = true, N = true, O = true, P = true, S = true}
Molecule.bond_types = {["-"] = 1, ["/"] = 1, ["\\"] = 1, ["="] = 2, ["#"] = 3, [":"] = 4}
local base_values = {1, 2, 3, 1}

function Molecule.fail(reason, column)
    error({reason = reason, column = column}, 0)
end

function Molecule.atom(element, aromatic, mass, charge, hydrogens, bracket, column)
    return {element = element, aromatic = aromatic == true, mass = mass or 0, charge = charge or 0,
        hydrogens = hydrogens or 0, bracket = bracket == true, column = column or 0}
end

function Molecule.new(elements)
    return setmetatable({elements = elements, atoms = {}, neighbors = {}, adjacency = {}, bonds = {},
        by_pair = {}, rings = {}, ring_atoms = {}, name = ""}, Molecule)
end

function Molecule:add_atom(atom)
    local number = #self.atoms + 1
    self.atoms[number], self.neighbors[number], self.adjacency[number] = atom, {}, {}
    return number
end

function Molecule:add_bond(first, second, symbol)
    local low, high = math.min(first, second), math.max(first, second)
    local bond = {first = low, second = high, symbol = symbol, multiplicity = 0, ring = false}
    self.bonds[#self.bonds + 1], self.by_pair[low .. ":" .. high] = bond, bond
    self.neighbors[first][second], self.neighbors[second][first] = bond, bond
    local one, two = self.adjacency[first], self.adjacency[second]
    one[#one + 1], two[#two + 1] = second, first
    table.sort(one)
    table.sort(two)
    return bond
end

function Molecule:ordered_bonds()
    local result = {}
    for i, bond in ipairs(self.bonds) do result[i] = bond end
    table.sort(result, function(a, b)
        if a.first ~= b.first then return a.first < b.first end
        return a.second < b.second
    end)
    for i, bond in ipairs(result) do bond.order = i end
    return result
end

function Molecule:base_total(number)
    local total = 0
    for _, bond in pairs(self.neighbors[number]) do total = total + base_values[bond.kind] end
    return total
end

function Molecule:bond_total(number)
    local total = 0
    for _, bond in pairs(self.neighbors[number]) do total = total + bond.multiplicity end
    return total
end

function Molecule.read_elements()
    local elements = {}
    for line in io.lines("input/elements.txt") do
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local symbol, number, weight, list = line:match("^(%S+) (%d+) (%d+) (%S+)$")
            local valences = {}
            for value in list:gmatch("%d+") do valences[#valences + 1] = tonumber(value) end
            elements[symbol] = {symbol = symbol, number = tonumber(number), weight = tonumber(weight), valences = valences}
        end
    end
    return elements
end

function Molecule.needs_pi(molecule, number, hydrogens)
    local atom = molecule.atoms[number]
    if hydrogens == nil then hydrogens = atom.hydrogens end
    return atom.aromatic and atom.element.valences[1] + atom.charge >= molecule:base_total(number) + hydrogens + 1
end

function Molecule.organic_hydrogens(atom, total)
    for _, valence in ipairs(atom.element.valences) do if valence >= total then return valence - total end end
end

return Molecule
