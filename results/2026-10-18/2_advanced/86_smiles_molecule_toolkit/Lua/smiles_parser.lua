local Molecule = require("molecule")
local Parser = {}

function Parser.organic(text, position)
    local pair, character = text:sub(position, position + 1), text:sub(position, position)
    if pair == "Cl" or pair == "Br" then return pair, false, position + 2 end
    if character ~= "" and ("BCNOPSFI"):find(character, 1, true) then return character, false, position + 1 end
    if character ~= "" and ("bcnops"):find(character, 1, true) then return character:upper(), true, position + 1 end
end

local function digit(character)
    return character ~= "" and character >= "0" and character <= "9"
end

function Parser.bracket(content, elements, column)
    local position = 1
    while digit(content:sub(position, position)) do position = position + 1 end
    if position >= 5 or (position > 1 and content:sub(1, 1) == "0") then Molecule.fail("bad bracket atom", column) end
    local mass = position > 1 and tonumber(content:sub(1, position - 1)) or 0
    local character = content:sub(position, position)
    if character == "" then Molecule.fail("bad bracket atom", column) end
    local symbol, aromatic
    if ("bcnops"):find(character, 1, true) then symbol, aromatic, position = character:upper(), true, position + 1
    elseif character >= "A" and character <= "Z" then
        local pair = content:sub(position, position + 1)
        local next_character = pair:sub(2, 2)
        if #pair == 2 and next_character >= "a" and next_character <= "z" and elements[pair] then symbol, position = pair, position + 2
        elseif elements[character] then symbol, position = character, position + 1
        else Molecule.fail("unknown element", column) end
        aromatic = false
    else Molecule.fail("bad bracket atom", column) end
    if content:sub(position, position + 1) == "@@" then position = position + 2
    elseif content:sub(position, position) == "@" then position = position + 1 end
    local hydrogens, charge = 0, 0
    if content:sub(position, position) == "H" then
        hydrogens, position = 1, position + 1
        if digit(content:sub(position, position)) then hydrogens, position = tonumber(content:sub(position, position)), position + 1 end
    end
    character = content:sub(position, position)
    if character == "+" or character == "-" then
        charge, position = character == "+" and 1 or -1, position + 1
        character = content:sub(position, position)
        if character >= "1" and character <= "9" then charge, position = charge * tonumber(character), position + 1 end
    end
    if position ~= #content + 1 then Molecule.fail("bad bracket atom", column) end
    return Molecule.atom(elements[symbol], aromatic, mass, charge, hydrogens, true, column)
end

function Parser.atom(text, position, elements)
    if text:sub(position, position) == "[" then
        local close = text:find("]", position + 1, true)
        if not close then Molecule.fail("unclosed bracket", position) end
        return Parser.bracket(text:sub(position + 1, close - 1), elements, position), close + 1
    end
    local symbol, aromatic, next_position = Parser.organic(text, position)
    if not symbol then Molecule.fail("unexpected character", position) end
    return Molecule.atom(elements[symbol], aromatic, 0, 0, 0, false, position), next_position
end

function Parser.parse(text, elements, atom_reader, pattern)
    local molecule, current, pending = Molecule.new(elements), nil, nil
    local branches, open_rings, position = {}, {}, 1
    atom_reader = atom_reader or Parser.atom
    local symbols = pattern and {["-"] = 1, ["="] = 2, ["#"] = 3, [":"] = 4, ["~"] = 5} or Molecule.bond_types
    while position <= #text do
        local character, column = text:sub(position, position), position
        if symbols[character] then
            if not current or pending then Molecule.fail("misplaced bond", column) end
            pending, position = {symbol = character, column = column}, position + 1
        elseif character == "(" then
            if not current or pending or text:sub(position - 1, position - 1) == "(" then Molecule.fail("misplaced branch", column) end
            branches[#branches + 1], position = {atom = current, column = column}, position + 1
        elseif character == ")" then
            if #branches == 0 then Molecule.fail("unmatched parenthesis", column) end
            if pending then Molecule.fail("dangling bond", pending.column) end
            if text:sub(position - 1, position - 1) == "(" then Molecule.fail("empty branch", column) end
            current, position = table.remove(branches).atom, position + 1
        elseif digit(character) or character == "%" then
            if not current then Molecule.fail("misplaced ring closure", column) end
            local ring
            if character == "%" then
                local value = text:sub(position + 1, position + 2)
                if #value ~= 2 or not value:match("^%d%d$") then Molecule.fail("bad ring number", column) end
                ring, position = tonumber(value), position + 3
            else ring, position = tonumber(character), position + 1 end
            local symbol = pending and pending.symbol or nil
            pending = nil
            local opening = open_rings[ring]
            if not opening then open_rings[ring] = {atom = current, symbol = symbol, column = column}
            else
                if opening.atom == current then Molecule.fail("self bond", column) end
                if opening.symbol and symbol and symbols[opening.symbol] ~= symbols[symbol] then Molecule.fail("ring bond mismatch", column) end
                if molecule.neighbors[opening.atom][current] then Molecule.fail("duplicate bond", column) end
                molecule:add_bond(opening.atom, current, symbol or opening.symbol)
                open_rings[ring] = nil
            end
        else
            local atom, next_position = atom_reader(text, position, elements)
            local new_atom = molecule:add_atom(atom)
            if current then molecule:add_bond(current, new_atom, pending and pending.symbol or nil) end
            current, pending, position = new_atom, nil, next_position
        end
    end
    if pending then Molecule.fail("dangling bond", pending.column) end
    if #branches > 0 then Molecule.fail("unmatched parenthesis", branches[1].column) end
    local earliest
    for _, opening in pairs(open_rings) do earliest = math.min(earliest or opening.column, opening.column) end
    if earliest then Molecule.fail("unclosed ring", earliest) end
    return molecule
end

return Parser
