local Molecule = require("molecule")
local Parser = require("smiles_parser")
local Aromatic = require("rings_aromatic")
local Canonical = require("canonical")
local Search = require("search")
local argument_counts = {MATCH = {1, 1}, CONTAINS = {2, 2}, MATRIX = {2, 12}, NEAREST = {2, 2},
    WITHIN = {2, 2}, COMPARE = {2, 2}, CLUSTER = {1, 1}}
local system_kinds = {"isolated", "fused", "spiro", "bridged"}

local function append(items, value)
    items[#items + 1] = value
end

local function extend(items, values)
    for _, value in ipairs(values) do append(items, value) end
end

local function size(items)
    local result = 0
    for _ in pairs(items) do result = result + 1 end
    return result
end

local function split(line, separator)
    local result = {}
    separator = separator or " "
    local start = 1
    while true do
        local position = line:find(separator, start, true)
        if not position then append(result, line:sub(start)); break end
        append(result, line:sub(start, position - 1))
        start = position + #separator
    end
    return result
end

local function data_lines(filename)
    local result, number = {}, 0
    for line in io.lines("input/" .. filename) do
        number = number + 1
        if line ~= "" and line:sub(1, 1) ~= "#" then append(result, {number = number, line = line}) end
    end
    return result
end

local function valid_name(value)
    return value ~= nil and #value >= 1 and #value <= 32 and value:match("^[A-Za-z0-9_-]+$") ~= nil
end

local function valid_number(value, minimum, maximum)
    return value ~= nil and value:match("^%d+$") ~= nil and (#value == 1 or value:sub(1, 1) ~= "0")
        and tonumber(value) >= minimum and tonumber(value) <= maximum
end

local function threshold(value)
    local parts = split(value, "/")
    if #parts ~= 2 or not valid_number(parts[1], 0, 99) or not valid_number(parts[2], 1, 99) then return nil end
    local p, q = tonumber(parts[1]), tonumber(parts[2])
    if p <= q then return {p, q} end
end

local function fraction_text(value)
    local a, b = value[1], value[2]
    while b ~= 0 do a, b = b, a % b end
    return value[1] // a .. "/" .. value[2] // a
end

local function fraction_compare(first, second)
    local a, b = first[1] * second[2], second[1] * first[2]
    return a < b and -1 or a > b and 1 or 0
end

local function member_names(molecules)
    local names = {}
    for _, molecule in ipairs(molecules) do append(names, molecule.name) end
    return table.concat(names, ",")
end

local function analyze(molecule)
    Aromatic.find_rings(molecule)
    for _, bond in ipairs(molecule.bonds) do
        if bond.symbol then bond.kind = Molecule.bond_types[bond.symbol]
        else bond.kind = molecule.atoms[bond.first].aromatic and molecule.atoms[bond.second].aromatic and bond.ring and 4 or 1 end
    end
    local needing = {}
    for i = 1, #molecule.atoms do if Molecule.needs_pi(molecule, i) then append(needing, i) end end
    Aromatic.kekulize(molecule, needing)
    for i, atom in ipairs(molecule.atoms) do
        local total = molecule:bond_total(i)
        if atom.bracket then
            if total + atom.hydrogens > atom.element.valences[#atom.element.valences] + math.abs(atom.charge) then Molecule.fail("bad valence", atom.column) end
        else
            local hydrogens = Molecule.organic_hydrogens(atom, total)
            if hydrogens == nil then Molecule.fail("bad valence", atom.column) end
            atom.hydrogens = hydrogens
        end
    end
end

local function molecular_properties(molecule)
    local counts, hydrogens, weight, heavy, heavy_degrees, triple_ends, charge = {}, 0, 0, 0, {}, {}, 0
    for i, atom in ipairs(molecule.atoms) do
        local symbol = atom.element.symbol
        counts[symbol], hydrogens = (counts[symbol] or 0) + 1, hydrogens + atom.hydrogens
        weight, charge = weight + (atom.mass ~= 0 and atom.mass * 1000 or atom.element.weight), charge + atom.charge
        if symbol ~= "H" then heavy = heavy + 1 end
        local degree = 0
        for _, neighbor in ipairs(molecule.adjacency[i]) do if molecule.atoms[neighbor].element.symbol ~= "H" then degree = degree + 1 end end
        heavy_degrees[i] = degree
    end
    counts.H, weight = (counts.H or 0) + hydrogens, weight + hydrogens * molecule.elements.H.weight
    local symbols = {}
    for symbol, count in pairs(counts) do if count > 0 then append(symbols, symbol) end end
    table.sort(symbols)
    if (counts.C or 0) > 0 then
        local ordered = {"C"}
        if counts.H > 0 then append(ordered, "H") end
        for _, symbol in ipairs(symbols) do if symbol ~= "C" and symbol ~= "H" then append(ordered, symbol) end end
        symbols = ordered
    end
    local formula = {}
    for _, symbol in ipairs(symbols) do append(formula, symbol .. (counts[symbol] == 1 and "" or tostring(counts[symbol]))) end
    for _, bond in ipairs(molecule.bonds) do if bond.multiplicity == 3 then triple_ends[bond.first], triple_ends[bond.second] = true, true end end
    local rotatable, donors, acceptors = 0, 0, 0
    for _, bond in ipairs(molecule.bonds) do
        if bond.multiplicity == 1 and not bond.ring and heavy_degrees[bond.first] >= 2 and heavy_degrees[bond.second] >= 2
            and not triple_ends[bond.first] and not triple_ends[bond.second] then rotatable = rotatable + 1 end
    end
    for i, atom in ipairs(molecule.atoms) do
        if atom.element.symbol == "N" or atom.element.symbol == "O" then
            acceptors = acceptors + 1
            local attached = atom.hydrogens
            for _, neighbor in ipairs(molecule.adjacency[i]) do if molecule.atoms[neighbor].element.symbol == "H" then attached = attached + 1 end end
            if attached >= 1 then donors = donors + 1 end
        end
    end
    local violations = (weight > 500000 and 1 or 0) + (donors > 5 and 1 or 0) + (acceptors > 10 and 1 or 0)
    return {formula = table.concat(formula), weight = weight, heavy = heavy, rotatable = rotatable, donors = donors,
        acceptors = acceptors, lipinski = violations <= 1 and "pass" or "fail", charge = charge}
end

local function scaffold_molecule(molecule)
    if #molecule.rings == 0 then return nil end
    local remaining = {}
    for i = 1, #molecule.atoms do remaining[i] = true end
    while true do
        local leaf
        for atom = 1, #molecule.atoms do
            if remaining[atom] and not molecule.ring_atoms[atom] then
                local degree = 0
                for _, neighbor in ipairs(molecule.adjacency[atom]) do if remaining[neighbor] then degree = degree + 1 end end
                if degree == 1 then leaf = atom; break end
            end
        end
        if not leaf then break end
        remaining[leaf] = nil
    end
    local kept = {}
    for atom in pairs(remaining) do
        kept[atom] = true
        for _, neighbor in ipairs(molecule.adjacency[atom]) do
            if not remaining[neighbor] and molecule.neighbors[atom][neighbor].kind == 2 then kept[neighbor] = true end
        end
    end
    local scaffold, renumber = Molecule.new(molecule.elements), {}
    for i, atom in ipairs(molecule.atoms) do
        if kept[i] then
            local hydrogens = atom.hydrogens
            for _, neighbor in ipairs(molecule.adjacency[i]) do if not kept[neighbor] then hydrogens = hydrogens + molecule.neighbors[i][neighbor].multiplicity end end
            renumber[i] = scaffold:add_atom(Molecule.atom(atom.element, atom.aromatic, atom.mass, atom.charge, hydrogens, atom.bracket, atom.column))
        end
    end
    for _, original in ipairs(molecule:ordered_bonds()) do
        if kept[original.first] and kept[original.second] then
            local bond = scaffold:add_bond(renumber[original.first], renumber[original.second], original.symbol)
            bond.kind, bond.multiplicity, bond.ring = original.kind, original.multiplicity, original.ring
        end
    end
    for _, ring in ipairs(molecule.rings) do
        local copied = {}
        for _, atom in ipairs(ring) do append(copied, renumber[atom]) end
        append(scaffold.rings, copied)
    end
    for atom in pairs(molecule.ring_atoms) do scaffold.ring_atoms[renumber[atom]] = true end
    return scaffold
end

local function ring_systems(molecule)
    local atom_sets, connections, relations = {}, {}, {}
    for i, ring in ipairs(molecule.rings) do
        local atoms = {}
        for _, atom in ipairs(ring) do atoms[atom] = true end
        atom_sets[i], connections[i] = atoms, {}
    end
    for i = 1, #atom_sets do
        for j = i + 1, #atom_sets do
            local shared = {}
            for _, atom in ipairs(molecule.rings[i]) do if atom_sets[j][atom] then append(shared, atom) end end
            if #shared > 0 then
                connections[i][j], connections[j][i] = true, true
                local kind = #shared == 1 and "spiro" or "bridged"
                if #shared == 2 and molecule.neighbors[shared[1]][shared[2]] then kind = "fused" end
                append(relations, {i, j, kind})
            end
        end
    end
    local systems, seen = {}, {}
    for start = 1, #atom_sets do
        if not seen[start] then
            local queue, head, component, members, atoms = {start}, 1, {[start] = true}, {}, {}
            seen[start] = true
            while head <= #queue do
                local ring = queue[head]
                head = head + 1
                append(members, ring)
                for atom in pairs(atom_sets[ring]) do atoms[atom] = true end
                for neighbor = 1, #atom_sets do
                    if connections[ring][neighbor] and not seen[neighbor] then seen[neighbor], component[neighbor] = true, true; append(queue, neighbor) end
                end
            end
            table.sort(members)
            local kinds = {}
            for _, relation in ipairs(relations) do if component[relation[1]] and component[relation[2]] then kinds[relation[3]] = true end end
            local kind = #members == 1 and "isolated" or kinds.bridged and "bridged" or kinds.fused and "fused" or "spiro"
            append(systems, {rings = members, atoms = size(atoms), kind = kind})
        end
    end
    return systems
end

local function read_molecules(elements, causes)
    local molecules, errors, reserved = {}, {}, {}
    local lines = data_lines("molecules.smi")
    for _, record in ipairs(lines) do
        local tokens = split(record.line)
        if #tokens ~= 2 or tokens[1] == "" or not valid_name(tokens[2]) then
            append(errors, "line " .. record.number .. ": bad line")
            causes["bad line"] = (causes["bad line"] or 0) + 1
        elseif reserved[tokens[2]] then
            append(errors, "line " .. record.number .. " " .. tokens[2] .. ": duplicate name")
            causes["duplicate name"] = (causes["duplicate name"] or 0) + 1
        else
            local smiles, name = tokens[1], tokens[2]
            reserved[name] = true
            local ok, molecule = pcall(function()
                local parsed = Parser.parse(smiles, elements)
                analyze(parsed)
                return parsed
            end)
            if ok then
                molecule.name, molecule.order = name, #molecules + 1
                append(molecules, molecule)
            else
                if type(molecule) ~= "table" or not molecule.reason then error(molecule, 0) end
                append(errors, string.format("line %d %s: %s at column %d", record.number, name, molecule.reason, molecule.column))
                causes[molecule.reason] = (causes[molecule.reason] or 0) + 1
            end
        end
    end
    local paragraph = {string.format("MOLECULES lines=%d valid=%d errors=%d", #lines, #molecules, #errors)}
    extend(paragraph, errors)
    return molecules, paragraph
end

local function prepare_molecules(molecules)
    for _, molecule in ipairs(molecules) do
        molecule.properties = molecular_properties(molecule)
        molecule.canonical, molecule.classes = Canonical.canonicalize(molecule)
        local scaffold = scaffold_molecule(molecule)
        if scaffold then molecule.scaffold = Canonical.canonicalize(scaffold) end
        molecule.systems, molecule.aromatic_rings = ring_systems(molecule), {}
        for i, ring in ipairs(molecule.rings) do
            local aromatic = true
            for _, atom in ipairs(ring) do if not molecule.atoms[atom].aromatic then aromatic = false; break end end
            molecule.aromatic_rings[i] = aromatic
        end
        molecule.bits, molecule.paths = Search.fingerprint(molecule)
    end
end

local function check_arguments(query, elements, by_name)
    local kind, arguments = query.type, query.arguments
    local bounds = argument_counts[kind]
    if #arguments < bounds[1] or #arguments > bounds[2] then return "bad arguments" end
    if kind == "MATCH" then
        local ok, pattern = pcall(Parser.parse, arguments[1], elements, Search.read_atom, true)
        if not ok then
            if type(pattern) ~= "table" or not pattern.reason then error(pattern, 0) end
            return string.format("bad pattern %s at column %d", pattern.reason, pattern.column)
        end
        query.pattern = pattern
    elseif kind == "CLUSTER" then
        query.threshold = threshold(arguments[1])
        if not query.threshold then return "bad threshold" end
    elseif kind == "CONTAINS" or kind == "MATRIX" or kind == "COMPARE" then
        for _, name in ipairs(arguments) do if not by_name[name] then return "unknown molecule " .. name end end
        local seen = {}
        for _, name in ipairs(arguments) do if seen[name] then return "repeated molecule" end; seen[name] = true end
    else
        if not by_name[arguments[1]] then return "unknown molecule " .. arguments[1] end
        if kind == "NEAREST" then
            if not valid_number(arguments[2], 1, 99) then return "bad count" end
            query.count = tonumber(arguments[2])
        else
            query.threshold = threshold(arguments[2])
            if not query.threshold then return "bad threshold" end
        end
    end
end

local function query_error(line, kind, identifier, reason, causes)
    local text
    if reason == "unknown query" then text = "line " .. line .. ": unknown query"
    elseif reason == "bad id" then text = "line " .. line .. " " .. kind .. ": bad id"
    else text = "line " .. line .. " " .. kind .. " " .. identifier .. ": " .. reason end
    local cause = reason
    if reason:sub(1, 12) == "bad pattern " then cause = "bad pattern"
    elseif reason:sub(1, 17) == "unknown molecule " then cause = "unknown molecule" end
    causes[cause] = (causes[cause] or 0) + 1
    return text
end

local function read_queries(elements, by_name, causes)
    local queries, errors, reserved = {}, {}, {}
    local lines = data_lines("queries.txt")
    for _, record in ipairs(lines) do
        local tokens = split(record.line)
        local kind, identifier, reason = tokens[1], tokens[2]
        if not argument_counts[kind] then reason = "unknown query"
        elseif not valid_name(identifier) then reason = "bad id"
        elseif reserved[identifier] then reason = "duplicate id"
        else
            reserved[identifier] = true
            local arguments = {}
            for i = 3, #tokens do append(arguments, tokens[i]) end
            local query = {type = kind, id = identifier, arguments = arguments}
            reason = check_arguments(query, elements, by_name)
            if not reason then append(queries, query) end
        end
        if reason then append(errors, query_error(record.number, kind, identifier, reason, causes)) end
    end
    local paragraph = {string.format("QUERIES lines=%d valid=%d errors=%d", #lines, #queries, #errors)}
    extend(paragraph, errors)
    return queries, paragraph
end

local function properties_lines(molecules)
    local lines = {"name,formula,weight,heavy_atoms,rings,rotatable,donors,acceptors,lipinski"}
    for _, molecule in ipairs(molecules) do
        local p = molecule.properties
        append(lines, string.format("%s,%s,%d.%03d,%d,%d,%d,%d,%d,%s", molecule.name, p.formula, p.weight // 1000,
            p.weight % 1000, p.heavy, #molecule.rings, p.rotatable, p.donors, p.acceptors, p.lipinski))
    end
    return lines
end

local function canonical_paragraphs(molecules)
    local by_canonical, canonical_order, by_formula, formula_order, by_scaffold, acyclic = {}, {}, {}, {}, {}, 0
    for _, molecule in ipairs(molecules) do
        local smiles, formula = molecule.canonical, molecule.properties.formula
        if not by_canonical[smiles] then by_canonical[smiles] = {}; append(canonical_order, smiles) end
        append(by_canonical[smiles], molecule)
        if not by_formula[formula] then by_formula[formula] = {}; append(formula_order, formula) end
        append(by_formula[formula], molecule)
        if molecule.scaffold then
            by_scaffold[molecule.scaffold] = by_scaffold[molecule.scaffold] or {}
            append(by_scaffold[molecule.scaffold], molecule)
        else acyclic = acyclic + 1 end
    end
    local canonical = {string.format("CANONICAL molecules=%d unique=%d", #molecules, #canonical_order)}
    for _, molecule in ipairs(molecules) do
        local charge = molecule.properties.charge
        append(canonical, string.format("%s %s classes=%d charge=%s", molecule.name, molecule.canonical, molecule.classes,
            charge == 0 and "0" or string.format("%+d", charge)))
    end
    local groups, count = {}, 0
    for _, smiles in ipairs(canonical_order) do
        if #by_canonical[smiles] >= 2 then append(groups, smiles); count = count + #by_canonical[smiles] end
    end
    local duplicates = {string.format("DUPLICATES groups=%d molecules=%d", #groups, count)}
    for i, smiles in ipairs(groups) do append(duplicates, string.format("group %d %s members=%s", i, smiles, member_names(by_canonical[smiles]))) end
    groups = {}
    for _, formula in ipairs(formula_order) do
        local forms = {}
        for _, molecule in ipairs(by_formula[formula]) do forms[molecule.canonical] = true end
        if size(forms) >= 2 then append(groups, {formula = formula, forms = size(forms)}) end
    end
    local isomers = {"ISOMERS groups=" .. #groups}
    for i, group in ipairs(groups) do append(isomers, string.format("isomer %d %s forms=%d members=%s", i,
        group.formula, group.forms, member_names(by_formula[group.formula]))) end
    groups = {}
    for smiles in pairs(by_scaffold) do append(groups, smiles) end
    table.sort(groups, function(a, b)
        if #by_scaffold[a] ~= #by_scaffold[b] then return #by_scaffold[a] > #by_scaffold[b] end
        return a < b
    end)
    local scaffolds = {string.format("SCAFFOLDS distinct=%d acyclic=%d", #groups, acyclic)}
    for i, smiles in ipairs(groups) do append(scaffolds, string.format("scaffold %d %s count=%d members=%s",
        i, smiles, #by_scaffold[smiles], member_names(by_scaffold[smiles]))) end
    return {canonical, duplicates, isomers, scaffolds}
end

local function ring_paragraphs(molecules)
    local paragraphs, sizes, kinds, total_aromatic, total_rings = {}, {}, {}, 0, 0
    for _, molecule in ipairs(molecules) do
        if #molecule.rings > 0 then
            local aromatic, ring_bonds = 0, 0
            for _, flag in ipairs(molecule.aromatic_rings) do if flag then aromatic = aromatic + 1 end end
            for _, bond in ipairs(molecule.bonds) do if bond.ring then ring_bonds = ring_bonds + 1 end end
            total_aromatic, total_rings = total_aromatic + aromatic, total_rings + #molecule.rings
            local paragraph = {string.format("MOLECULE %s atoms=%d bonds=%d rings=%d aromatic=%d systems=%d ring_atoms=%d ring_bonds=%d",
                molecule.name, #molecule.atoms, #molecule.bonds, #molecule.rings, aromatic, #molecule.systems, size(molecule.ring_atoms), ring_bonds)}
            for i, ring in ipairs(molecule.rings) do
                local hetero = 0
                for _, atom in ipairs(ring) do if molecule.atoms[atom].element.symbol ~= "C" then hetero = hetero + 1 end end
                append(paragraph, string.format("ring %d size=%d aromatic=%s hetero=%d atoms=%s", i, #ring,
                    molecule.aromatic_rings[i] and "yes" or "no", hetero, table.concat(ring, "-")))
                sizes[#ring] = (sizes[#ring] or 0) + 1
            end
            for i, system in ipairs(molecule.systems) do
                kinds[system.kind] = (kinds[system.kind] or 0) + 1
                append(paragraph, string.format("system %d kind=%s rings=%s atoms=%d", i, system.kind, table.concat(system.rings, ","), system.atoms))
            end
            local doubles = {}
            for _, bond in ipairs(molecule:ordered_bonds()) do if bond.kind == 4 and bond.multiplicity == 2 then append(doubles, bond.first .. "=" .. bond.second) end end
            append(paragraph, "kekule " .. (#doubles == 0 and "-" or table.concat(doubles, " ")))
            append(paragraphs, paragraph)
        end
    end
    local summary = {string.format("SUMMARY molecules=%d cyclic=%d rings=%d aromatic=%d", #molecules, #paragraphs, total_rings, total_aromatic)}
    local keys, entries = {}, {}
    for k in pairs(sizes) do append(keys, k) end
    table.sort(keys)
    for _, k in ipairs(keys) do append(entries, k .. "=" .. sizes[k]) end
    append(summary, "sizes " .. (#entries == 0 and "-" or table.concat(entries, " ")))
    entries = {}
    for _, kind in ipairs(system_kinds) do append(entries, kind .. "=" .. (kinds[kind] or 0)) end
    append(summary, "systems " .. table.concat(entries, " "))
    append(paragraphs, summary)
    return paragraphs
end

local function substructure_paragraphs(queries, molecules, by_name)
    local paragraphs, patterns, hits, contains, found = {}, 0, 0, 0, 0
    for _, query in ipairs(queries) do
        if query.type == "MATCH" then
            patterns = patterns + 1
            local matches, total, top = {}, 0, nil
            for _, molecule in ipairs(molecules) do
                local count, unique, mapping = Search.embeddings(query.pattern, molecule)
                if count > 0 then
                    local record = {molecule = molecule, count = count, unique = unique, mapping = mapping}
                    append(matches, record)
                    total = total + count
                    if not top or count > top.count then top = record end
                end
            end
            hits = hits + #matches
            local paragraph = {string.format("MATCH %s %s atoms=%d bonds=%d hits=%d embeddings=%d", query.id,
                query.arguments[1], #query.pattern.atoms, #query.pattern.bonds, #matches, total)}
            for _, match in ipairs(matches) do append(paragraph, string.format("%s count=%d unique=%d map=%s",
                match.molecule.name, match.count, match.unique, table.concat(match.mapping, ","))) end
            if top then append(paragraph, string.format("top %s count=%d", top.molecule.name, top.count)) end
            append(paragraphs, paragraph)
        elseif query.type == "CONTAINS" then
            contains = contains + 1
            local first, second = by_name[query.arguments[1]], by_name[query.arguments[2]]
            local count, unique, mapping = Search.embeddings(Search.molecule_pattern(first), second)
            local line = string.format("CONTAINS %s %s %s result=", query.id, first.name, second.name)
            if count > 0 then
                found = found + 1
                line = line .. string.format("yes count=%d unique=%d map=%s", count, unique, table.concat(mapping, ","))
            else line = line .. "no" end
            append(paragraphs, {line})
        end
    end
    append(paragraphs, {string.format("SUMMARY patterns=%d hits=%d contains=%d found=%d", patterns, hits, contains, found)})
    return paragraphs
end

local function similarities()
    local cache = {}
    return function(first, second)
        local a, b = math.min(first.order, second.order), math.max(first.order, second.order)
        local key = a .. ":" .. b
        if not cache[key] then cache[key] = Search.tanimoto(first.bits, second.bits) end
        return cache[key]
    end
end

local function matrix_paragraph(query, by_name, get)
    local molecules = {}
    for _, name in ipairs(query.arguments) do append(molecules, by_name[name]) end
    local paragraph = {string.format("MATRIX %s size=%d", query.id, #molecules)}
    for _, first in ipairs(molecules) do
        local row = {}
        for _, second in ipairs(molecules) do append(row, fraction_text(get(first, second))) end
        append(paragraph, "row " .. first.name .. " " .. table.concat(row, " "))
    end
    local best_first, best_second, best = molecules[1], molecules[2], get(molecules[1], molecules[2])
    for i, first in ipairs(molecules) do
        for j = i + 1, #molecules do
            local value = get(first, molecules[j])
            if fraction_compare(value, best) > 0 then best_first, best_second, best = first, molecules[j], value end
        end
    end
    append(paragraph, "best " .. best_first.name .. " " .. best_second.name .. " " .. fraction_text(best))
    return paragraph
end

local function neighbors_paragraph(query, molecules, by_name, get)
    local source, neighbors = by_name[query.arguments[1]], {}
    for _, molecule in ipairs(molecules) do
        if molecule ~= source then append(neighbors, {molecule = molecule, value = get(source, molecule)}) end
    end
    table.sort(neighbors, function(a, b)
        local difference = fraction_compare(a.value, b.value)
        if difference ~= 0 then return difference > 0 end
        return a.molecule.order < b.molecule.order
    end)
    local selected, heading = {}, nil
    if query.type == "NEAREST" then
        for i = 1, math.min(query.count, #neighbors) do append(selected, neighbors[i]) end
        heading = string.format("NEAREST %s %s count=%d", query.id, source.name, #selected)
    else
        for _, neighbor in ipairs(neighbors) do if fraction_compare(neighbor.value, query.threshold) >= 0 then append(selected, neighbor) end end
        heading = string.format("WITHIN %s %s threshold=%s count=%d", query.id, source.name, fraction_text(query.threshold), #selected)
    end
    local paragraph = {heading}
    for i, neighbor in ipairs(selected) do append(paragraph, string.format("%d %s %s common=%d", i,
        neighbor.molecule.name, fraction_text(neighbor.value), neighbor.value[1])) end
    return paragraph
end

local function compare_paragraph(query, by_name, get)
    local first, second = by_name[query.arguments[1]], by_name[query.arguments[2]]
    local value = get(first, second)
    return {string.format("COMPARE %s %s %s bits=%d,%d common=%d union=%d tanimoto=%s identical=%s", query.id,
        first.name, second.name, size(first.bits), size(second.bits), value[1], value[2], fraction_text(value),
        first.canonical == second.canonical and "yes" or "no")}
end

local function cluster_paragraph(query, molecules, get)
    local neighbors, order = {}, {}
    for i, first in ipairs(molecules) do
        neighbors[i], order[i] = {}, i
        for j, second in ipairs(molecules) do
            if i ~= j and fraction_compare(get(first, second), query.threshold) >= 0 then append(neighbors[i], j) end
        end
    end
    table.sort(order, function(a, b)
        if #neighbors[a] ~= #neighbors[b] then return #neighbors[a] > #neighbors[b] end
        return a < b
    end)
    local assigned, clusters, singletons = {}, {}, 0
    for _, center in ipairs(order) do
        if not assigned[center] then
            local members = {center}
            for _, neighbor in ipairs(neighbors[center]) do if not assigned[neighbor] then append(members, neighbor) end end
            for _, member in ipairs(members) do assigned[member] = true end
            append(clusters, members)
            if #members == 1 then singletons = singletons + 1 end
        end
    end
    local paragraph = {string.format("CLUSTER %s threshold=%s clusters=%d singletons=%d", query.id, fraction_text(query.threshold), #clusters, singletons)}
    local number = 0
    for _, members in ipairs(clusters) do
        if #members >= 2 then
            number = number + 1
            local selected = {}
            for _, i in ipairs(members) do append(selected, molecules[i]) end
            append(paragraph, string.format("cluster %d centroid=%s size=%d members=%s", number, selected[1].name,
                #selected, member_names(selected)))
        end
    end
    return paragraph
end

local function similarity_paragraphs(queries, molecules, by_name)
    local fingerprints = {string.format("FINGERPRINTS molecules=%d size=1024 depth=5", #molecules)}
    for _, molecule in ipairs(molecules) do append(fingerprints, string.format("%s bits=%d paths=%d", molecule.name, size(molecule.bits), molecule.paths)) end
    local paragraphs, get = {fingerprints}, similarities()
    for _, query in ipairs(queries) do
        local paragraph
        if query.type == "MATRIX" then paragraph = matrix_paragraph(query, by_name, get)
        elseif query.type == "NEAREST" or query.type == "WITHIN" then paragraph = neighbors_paragraph(query, molecules, by_name, get)
        elseif query.type == "COMPARE" then paragraph = compare_paragraph(query, by_name, get)
        elseif query.type == "CLUSTER" then paragraph = cluster_paragraph(query, molecules, get) end
        if paragraph then append(paragraphs, paragraph) end
    end
    return paragraphs
end

local function causes_paragraph(causes)
    local reasons = {}
    for reason in pairs(causes) do append(reasons, reason) end
    table.sort(reasons, function(a, b)
        if causes[a] ~= causes[b] then return causes[a] > causes[b] end
        return a < b
    end)
    local paragraph = {"CAUSES kinds=" .. #reasons}
    for _, reason in ipairs(reasons) do append(paragraph, reason .. "=" .. causes[reason]) end
    return paragraph
end

local function paragraphs_text(paragraphs)
    local blocks = {}
    for _, paragraph in ipairs(paragraphs) do append(blocks, table.concat(paragraph, "\n")) end
    return table.concat(blocks, "\n\n") .. "\n"
end

local elements, causes = Molecule.read_elements(), {}
local molecules, molecule_errors = read_molecules(elements, causes)
prepare_molecules(molecules)
local by_name = {}
for _, molecule in ipairs(molecules) do by_name[molecule.name] = molecule end
local queries, query_errors = read_queries(elements, by_name, causes)
local outputs = {{"properties.csv", table.concat(properties_lines(molecules), "\n") .. "\n"},
    {"canonical.txt", paragraphs_text(canonical_paragraphs(molecules))}, {"rings.txt", paragraphs_text(ring_paragraphs(molecules))},
    {"substructure.txt", paragraphs_text(substructure_paragraphs(queries, molecules, by_name))},
    {"similarity.txt", paragraphs_text(similarity_paragraphs(queries, molecules, by_name))},
    {"errors.txt", paragraphs_text({molecule_errors, query_errors, causes_paragraph(causes)})}}
assert(os.execute("mkdir -p output"))
for _, output in ipairs(outputs) do
    local file = assert(io.open("output/" .. output[1], "wb"))
    file:write(output[2])
    file:close()
end
