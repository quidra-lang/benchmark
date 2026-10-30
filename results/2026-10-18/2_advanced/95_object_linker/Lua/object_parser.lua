local O = {}
function O.belongs(name, prefix) return name == prefix or name:sub(1, #prefix + 1) == prefix .. "." end
function O.nobits(name) return O.belongs(name, ".bss") end
function O.strings(name) return O.belongs(name, ".rodata.str") end
function O.words(line)
    local words = {}
    for word in line:gmatch("%S+") do words[#words + 1] = word end
    return words
end
function O.lines(path)
    local lines = {}
    for line in io.lines(path) do lines[#lines + 1] = line end
    return lines
end
function O.parse(lines, index, name)
    local object = { name = name, sections = {}, section_names = {}, comdats = {}, symbols = {}, symbol_names = {} }
    while lines[index] ~= "end" do
        local words = O.words(lines[index])
        index = index + 1
        if words[1] == "section" then
            local section = { kind = "input", owner = object, name = words[2], alignment = tonumber(words[3]),
                size = tonumber(words[4]), contents = {}, nobits = O.nobits(words[2]), string = O.strings(words[2]),
                relocations = {}, live = false, merged_positions = {} }
            object.sections[#object.sections + 1], object.section_names[section.name] = section, section
            if not section.nobits then
                while #section.contents < section.size do
                    local hex = O.words(lines[index])[2]
                    for i = 1, #hex, 2 do section.contents[#section.contents + 1] = tonumber(hex:sub(i, i + 1), 16) end
                    index = index + 1
                end
            end
        elseif words[1] == "comdat" then
            local sections = {}
            for i = 3, #words do sections[#sections + 1] = object.section_names[words[i]] end
            object.comdats[#object.comdats + 1] = { words[2], sections }
        elseif words[1] == "symbol" then
            local kind = words[4] == "undef" and "undefined" or (words[4] == "common" and "common" or "defined")
            local symbol = { owner = object, name = words[2], binding = words[3], kind = kind, offset = 0, size = 0, alignment = 1 }
            if kind == "common" then symbol.size, symbol.alignment = tonumber(words[5]), tonumber(words[6])
            elseif kind == "defined" then symbol.section, symbol.offset = object.section_names[words[4]], tonumber(words[5]) end
            object.symbols[#object.symbols + 1], object.symbol_names[symbol.name] = symbol, symbol
        elseif words[1] == "reloc" then
            local section = object.section_names[words[2]]
            section.relocations[#section.relocations + 1] = { section = section, offset = tonumber(words[3]), type = words[4],
                symbol = object.symbol_names[words[5]], addend = tonumber(words[6]) }
        end
    end
    return object, index + 1
end
function O.read(name) return (O.parse(O.lines("input/" .. name), 1, name)) end
return O
