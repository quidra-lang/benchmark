local M = {}
local function fields(line, pattern)
    local result = {}
    for value in line:gmatch(pattern or '%S+') do result[#result + 1] = value end
    return result
end
local function rows(name)
    local result, first = {}, true
    for line in io.lines('input/' .. name .. '.csv') do
        if first then first = false else result[#result + 1] = fields(line, '[^,]+') end
    end
    return result
end
local function real(value) return tonumber(value) + 0.0 end
function M.read_model()
    local model = {nodes = {}, members = {}, sections = {}, materials = {}, supports = {}, cases = {}, combinations = {}, settings = {influence = {}, drawing = {}}}
    local node_index, member_index, section_index, material_index = {}, {}, {}, {}
    for i, row in ipairs(rows('nodes')) do model.nodes[i] = {identifier = tonumber(row[1]), x = tonumber(row[2]), y = tonumber(row[3])}; node_index[tonumber(row[1])] = i end
    for i, row in ipairs(rows('sections')) do model.sections[i] = {name = row[1], area = real(row[2]), inertia = real(row[3])}; section_index[row[1]] = i end
    for i, row in ipairs(rows('materials')) do
        model.materials[i] = {name = row[1], young = real(row[2]), yield_stress = real(row[3]), density = real(row[4]), expansion = real(row[5])}
        material_index[row[1]] = i
    end
    for i, row in ipairs(rows('members')) do
        model.members[i] = {identifier = tonumber(row[1]), start = node_index[tonumber(row[2])], finish = node_index[tonumber(row[3])], section = section_index[row[4]], material = material_index[row[5]], group = row[6]}
        member_index[tonumber(row[1])] = i
    end
    for _, row in ipairs(rows('supports')) do model.supports[#model.supports + 1] = {node = node_index[tonumber(row[1])], fixed = {row[2] == '1', row[3] == '1'}, prescribed = {real(row[4]), real(row[5])}} end
    local current
    for line in io.lines('input/loads.txt') do
        local f = fields(line)
        if f[1] == 'LOADCASE' then current = {name = f[2], lines = {}}
        elseif f[1] == 'END' then model.cases[#model.cases + 1] = current
        elseif f[1] == 'COMBINATION' then
            local combination = {name = f[2], terms = {}}
            for i = 3, #f, 2 do combination.terms[#combination.terms + 1] = {f[i], real(f[i + 1])} end
            model.combinations[#model.combinations + 1] = combination
        elseif f[1] == 'FORCE' then current.lines[#current.lines + 1] = {'FORCE', node_index[tonumber(f[2])], real(f[3]), real(f[4])}
        elseif f[1] == 'TEMPERATURE' then current.lines[#current.lines + 1] = {'TEMPERATURE', member_index[tonumber(f[2])], real(f[3])}
        else current.lines[#current.lines + 1] = {f[1]} end
    end
    local settings = model.settings
    for line in io.lines('input/params.txt') do
        local f = fields(line)
        local kind = f[1]
        if kind == 'deck' then settings.deck = {}; for i = 2, #f do settings.deck[#settings.deck + 1] = node_index[tonumber(f[i])] end
        elseif kind == 'influence' then settings.influence[#settings.influence + 1] = member_index[tonumber(f[2])]
        elseif kind == 'vehicle' then
            local axles = {}
            for i = 3, #f, 2 do axles[#axles + 1] = {tonumber(f[i]), real(f[i + 1])} end
            settings.vehicle = {tonumber(f[2]), axles}
        elseif kind == 'rating' then settings.rating = {f[2], real(f[3]), real(f[4])}
        elseif kind == 'slenderness' then settings.slenderness = {real(f[2]), real(f[3])}
        elseif kind == 'deflection' then settings.deflection = {f[2], tonumber(f[3])}
        elseif kind == 'vibration' then settings.vibration = {f[2], tonumber(f[3]), tonumber(f[4])}
        elseif kind == 'removal' then settings.removal = f[2]
        elseif kind == 'drawing' then settings.drawing[#settings.drawing + 1] = {f[2], tonumber(f[3]), tonumber(f[4]), tonumber(f[5])}
        else settings.utilization_map = {tonumber(f[2]), tonumber(f[3])} end
    end
    return model
end
return M
