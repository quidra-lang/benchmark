local O = require("object_parser")
local L = {}
function L.align(value, alignment) return (value + alignment - 1) // alignment * alignment end
function L.segment(name, base, length, fill, output_names)
    local segment = { name = name, base = base, length = length, fill = fill, paddr = base,
        outputs = {}, filesz = 0, memsz = 0, used = 0, image = {} }
    for _, output in ipairs(output_names) do
        segment.outputs[#segment.outputs + 1] = { name = output, segment = segment, nobits = O.nobits(output),
            sections = {}, base_components = {}, components = {}, address = 0, size = 0, alignment = 1 }
    end
    return segment
end
function L.find_output(section_name, outputs)
    for _, output in ipairs(outputs) do if O.belongs(section_name, output.name) then return output end end
end
function L.assign(segment)
    local cursor = segment.base
    segment.filesz = 0
    for _, output in ipairs(segment.outputs) do
        output.alignment = 1
        for _, component in ipairs(output.components) do output.alignment = math.max(output.alignment, component.alignment) end
        cursor = L.align(cursor, output.alignment)
        output.address = cursor
        for _, component in ipairs(output.components) do
            cursor = L.align(cursor, component.alignment)
            component.address, cursor = cursor, cursor + component.size
        end
        output.size = cursor - output.address
        if not output.nobits then segment.filesz = cursor - segment.base end
    end
    segment.memsz = cursor - segment.base
end
return L
