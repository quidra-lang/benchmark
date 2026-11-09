local O = require("object_parser")
local Archive = require("archive")
local Resolver = require("resolver")
local Layout = require("layout")
local Relocator = require("relocator")
local function keys(values)
    local result = {}
    for key in pairs(values) do result[#result + 1] = key end
    table.sort(result)
    return result
end
local function append(target, source) for _, value in ipairs(source) do target[#target + 1] = value end end
local function slice(values, first)
    local result = {}
    for i = first, #values do result[#result + 1] = values[i] end
    return result
end
local function read_script()
    local script = { segments = {}, loads = {}, kept = {}, sorted = {}, wrapped = {}, defines = {}, inputs = {},
        segment_names = {}, outputs = {}, output_names = {}, script_names = {} }
    for _, line in ipairs(O.lines("input/link.txt")) do
        local name, expression = line:match("^define ([^ ]+) = (.*)$")
        if name then script.defines[#script.defines + 1], script.script_names[name] = { name, expression }, true
        else
            local words = O.words(line)
            local kind = words[1]
            if kind == "entry" then script.entry = words[2]
            elseif kind == "gc" then script.gc = words[2] == "on"
            elseif kind == "segment" then
                local segment = Layout.segment(words[2], tonumber(words[3]), tonumber(words[4]), tonumber(words[5]), slice(words, 6))
                script.segments[#script.segments + 1], script.segment_names[segment.name] = segment, segment
                segment.order = #script.segments
                for _, output in ipairs(segment.outputs) do
                    script.outputs[#script.outputs + 1], script.output_names[output.name] = output, output
                end
            elseif kind == "load" then script.loads[#script.loads + 1] = { words[2], words[3] }
            elseif kind == "keep" then script.kept[words[2]] = true
            elseif kind == "sort" then script.sorted[words[2]] = true
            elseif kind == "wrap" then script.wrapped[words[2]] = true
            elseif kind == "checksum" then script.checksum = { words[2], words[3] }
            else script.inputs[#script.inputs + 1] = { kind, slice(words, 2) } end
        end
    end
    return script
end
local function merged_strings(sections)
    local merged = { kind = "merged", sections = sections, alignment = 1, address = 0,
        contents = {}, strings = 0, unique = 0, saved = 0 }
    local positions, original_size = {}, 0
    for _, section in ipairs(sections) do
        section.merged, original_size = merged, original_size + section.size
        local start = 0
        while start < section.size do
            local ending, characters = start, {}
            repeat
                local byte = section.contents[ending + 1]
                characters[#characters + 1], ending = string.char(byte), ending + 1
            until section.contents[ending] == 0
            local value = table.concat(characters)
            if positions[value] == nil then
                positions[value], merged.unique = #merged.contents, merged.unique + 1
                for i = start + 1, ending do merged.contents[#merged.contents + 1] = section.contents[i] end
            end
            section.merged_positions[start], merged.strings = positions[value], merged.strings + 1
            start = ending
        end
    end
    merged.size, merged.saved = #merged.contents, original_size - #merged.contents
    return merged
end
local B = {}
B.__index = B
function B.new(script)
    local result = setmetatable({ script = script, objects = {}, entries = {}, archives = {}, comdats = {}, comdat_order = {},
        extractions = {}, orphans = {}, script_values = {}, veneers = {}, far_calls = {}, applied = {}, relocation_counts = {} }, B)
    for _, kind in ipairs(Relocator.types) do result.relocation_counts[kind] = { ok = 0, veneer = 0, overflow = 0, undefined = 0, total = 0 } end
    return result
end
function B:defined(name)
    if self.script.script_names[name] then return true end
    for _, entry in ipairs(self.entries[name] or {}) do if entry.kind == "defined" or entry.kind == "common" then return true end end
    return false
end
function B:undefined(name)
    if self:defined(name) then return false end
    if name == self.script.entry then return true end
    for _, entry in ipairs(self.entries[name] or {}) do if entry.kind == "undefined" and entry.binding == "global" then return true end end
    return false
end
function B:load_object(object)
    object.order = #self.objects + 1
    for _, group in ipairs(object.comdats) do
        local signature, sections = group[1], group[2]
        if self.comdats[signature] then
            local discarded = self.comdats[signature].discarded
            discarded[#discarded + 1] = object.name
            for _, section in ipairs(sections) do section.discard_reason = "comdat" end
        else
            self.comdats[signature] = { keeper = object.name, discarded = {} }
            self.comdat_order[#self.comdat_order + 1] = signature
        end
    end
    for _, symbol in ipairs(object.symbols) do
        if symbol.binding ~= "local" and symbol.kind == "defined" and symbol.section.discard_reason == "comdat" then
            symbol.kind, symbol.section = "undefined", nil
        end
    end
    object.symbol_names = {}
    for _, symbol in ipairs(object.symbols) do
        if symbol.kind == "undefined" then
            if self.script.wrapped[symbol.name] then symbol.name = "__wrap_" .. symbol.name
            elseif symbol.name:sub(1, 7) == "__real_" and self.script.wrapped[symbol.name:sub(8)] then symbol.name = symbol.name:sub(8) end
        end
        object.symbol_names[symbol.name] = symbol
        if symbol.binding ~= "local" then
            self.entries[symbol.name] = self.entries[symbol.name] or {}
            local entries = self.entries[symbol.name]
            entries[#entries + 1] = symbol
        end
    end
    self.objects[#self.objects + 1] = object
end
function B:extract(object, reason)
    local referrer = "*entry*"
    for _, entry in ipairs(self.entries[reason] or {}) do
        if entry.kind == "undefined" and entry.binding == "global" then referrer = entry.owner.name; break end
    end
    self.extractions[#self.extractions + 1] = { object.name, referrer, reason }
    self:load_object(object)
end
function B:scan_archive(name)
    if not self.archives[name] then self.archives[name] = Archive.read(name) end
    return Archive.scan(self.archives[name], function(symbol) return self:undefined(symbol) end,
        function(object, reason) self:extract(object, reason) end)
end
function B:load_inputs()
    for _, input in ipairs(self.script.inputs) do
        local kind, names = input[1], input[2]
        if kind == "object" then self:load_object(O.read(names[1]))
        elseif kind == "library" then self:scan_archive(names[1])
        else
            while true do
                local count = 0
                for _, name in ipairs(names) do count = count + self:scan_archive(name) end
                if count == 0 then break end
            end
        end
    end
    self.names, self.commons = Resolver.resolve(self.entries, self.script.script_names), {}
    self.ordered_names = keys(self.names)
    for _, name in ipairs(self.ordered_names) do if self.names[name].kind == "common" then self.commons[#self.commons + 1] = self.names[name] end end
end
function B:assign_outputs()
    self.candidates = {}
    for _, object in ipairs(self.objects) do
        for _, section in ipairs(object.sections) do
            if section.discard_reason ~= "comdat" then
                section.output = Layout.find_output(section.name, self.script.outputs)
                if not section.output then
                    section.discard_reason, self.orphans[section.name] = "orphan", (self.orphans[section.name] or 0) + 1
                else
                    local sections = section.output.sections
                    sections[#sections + 1] = section
                    self.candidates[#self.candidates + 1] = section
                    section.rank = #self.candidates
                end
            end
        end
    end
end
function B:target(symbol)
    if symbol.binding == "local" then return symbol.section end
    local resolution = self.names[symbol.name]
    if resolution.kind == "global" or resolution.kind == "weak" then return resolution.definition.section end
    if resolution.kind == "common" then return resolution end
end
function B:collect_garbage()
    local units, pending = {}, {}
    for _, section in ipairs(self.candidates) do units[section] = true end
    for _, common in ipairs(self.commons) do units[common] = true end
    if not self.script.gc then for unit in pairs(units) do unit.live = true end
    else
        for _, section in ipairs(self.candidates) do if self.script.kept[section.output.name] then pending[#pending + 1] = section end end
        local entry = self.names[self.script.entry]
        if entry then
            if entry.kind == "global" or entry.kind == "weak" then pending[#pending + 1] = entry.definition.section
            elseif entry.kind == "common" then pending[#pending + 1] = entry end
        end
        while #pending > 0 do
            local unit = table.remove(pending)
            if units[unit] and not unit.live then
                unit.live = true
                if unit.kind == "input" then
                    for _, relocation in ipairs(unit.relocations) do
                        local target = self:target(relocation.symbol)
                        if target then pending[#pending + 1] = target end
                    end
                end
            end
        end
    end
    for _, section in ipairs(self.candidates) do if not section.live then section.discard_reason = "gc" end end
    for _, object in ipairs(self.objects) do
        local unresolved = {}
        for _, section in ipairs(object.sections) do
            if section.live then
                for _, relocation in ipairs(section.relocations) do
                    local symbol = relocation.symbol
                    if symbol.binding ~= "local" and self.names[symbol.name].kind == "undefined" then unresolved[symbol.name] = true end
                end
            end
        end
        for name in pairs(unresolved) do
            local referrers = self.names[name].unresolved_referrers
            referrers[#referrers + 1] = object.name
        end
    end
end
function B:build_components()
    for _, output in ipairs(self.script.outputs) do
        local sections, strings = {}, {}
        for _, section in ipairs(output.sections) do if section.live then sections[#sections + 1] = section end end
        if self.script.sorted[output.name] then
            local function priority(section) return section.name == output.name and 65536 or tonumber(section.name:sub(#output.name + 2)) end
            table.sort(sections, function(a, b) return priority(a) < priority(b) or (priority(a) == priority(b) and a.rank < b.rank) end)
        end
        for _, section in ipairs(sections) do if section.string then strings[#strings + 1] = section end end
        local merged = #strings > 0 and merged_strings(strings) or false
        local components, inserted = {}, false
        for _, section in ipairs(sections) do
            if section.string then
                if not inserted then components[#components + 1], inserted = merged, true end
            else components[#components + 1] = section end
        end
        if output.name == ".bss" then
            local commons = {}
            for _, common in ipairs(self.commons) do if common.live then commons[#commons + 1] = common end end
            table.sort(commons, function(a, b) return a.alignment > b.alignment or (a.alignment == b.alignment and a.name < b.name) end)
            append(components, commons)
        end
        output.base_components = components
        self.veneers[output] = {}
    end
end
function B:location_address(section, offset)
    if section.string then return section.merged.address + section.merged_positions[offset] end
    return section.address + offset
end
function B:definition_address(resolution)
    local definition = resolution.definition
    return self:location_address(definition.section, definition.offset)
end
function B:find_far_calls()
    local calls = {}
    for _, section in ipairs(self.candidates) do
        if section.live then
            for _, relocation in ipairs(section.relocations) do
                local symbol = relocation.symbol
                if relocation.type == "CALL24" and symbol.binding ~= "local" then
                    local resolution = self.names[symbol.name]
                    if resolution.kind == "global" or resolution.kind == "weak" then
                        local value = self:definition_address(resolution) + relocation.addend - section.address - relocation.offset
                        if value < -33554432 or value >= 33554432 then calls[relocation] = true end
                    end
                end
            end
        end
    end
    return calls
end
function B:perform_layout()
    self:build_components()
    while true do
        for _, output in ipairs(self.script.outputs) do
            output.components = { table.unpack(output.base_components) }
            for _, name in ipairs(keys(self.veneers[output])) do output.components[#output.components + 1] = self.veneers[output][name] end
        end
        for _, segment in ipairs(self.script.segments) do Layout.assign(segment) end
        local far_calls, changed = self:find_far_calls(), false
        for relocation in pairs(far_calls) do
            local output, name = relocation.section.output, relocation.symbol.name
            if not self.veneers[output][name] then
                self.veneers[output][name] = { kind = "veneer", output = output, name = name, size = 8, alignment = 4, address = 0 }
                changed = true
            end
        end
        if not changed then self.far_calls = far_calls; break end
    end
end
function B:load_addresses()
    local storage = {}
    for _, segment in ipairs(self.script.segments) do storage[segment.name] = segment.base + segment.memsz end
    for _, load in ipairs(self.script.loads) do
        local segment = self.script.segment_names[load[1]]
        segment.paddr = Layout.align(storage[load[2]], 4)
        storage[load[2]] = segment.paddr + segment.filesz
    end
    for _, segment in ipairs(self.script.segments) do segment.used = storage[segment.name] - segment.base end
end
local function script_expression(text, outputs, values)
    local tokens, position = {}, 1
    while position <= #text do
        local rest, ch = text:sub(position), text:sub(position, position)
        if ch == " " then position = position + 1
        else
            local token = rest:match("^0x[0-9a-f]+") or rest:match("^[0-9]+") or rest:match("^[A-Za-z_.][A-Za-z0-9_.]*") or ch
            tokens[#tokens + 1], position = token, position + #token
        end
    end
    local cursor, expression, term = 1
    local function take()
        local token = tokens[cursor]
        cursor = cursor + 1
        return token
    end
    term = function()
        local token = take()
        if token == "(" then local value = expression(); take(); return value end
        if token:match("^[0-9]") then return tonumber(token) end
        if tokens[cursor] ~= "(" then return values[token] end
        take()
        if token == "align" then
            local value = expression()
            take()
            local alignment = expression()
            take()
            return Layout.align(value, alignment)
        end
        local output = outputs[take()]
        take()
        if token == "start" then return output.address elseif token == "end" then return output.address + output.size
        elseif token == "size" then return output.size end
        return output.segment.paddr + output.address - output.segment.base
    end
    expression = function()
        local value = term()
        while tokens[cursor] == "+" or tokens[cursor] == "-" do
            local operator, right = take(), term()
            if operator == "+" then value = value + right else value = value - right end
        end
        return value
    end
    return expression()
end
function B:evaluate_defines()
    for _, define in ipairs(self.script.defines) do self.script_values[define[1]] = script_expression(define[2], self.script.output_names, self.script_values) end
end
function B:symbol_value(symbol)
    if symbol.binding == "local" then return self:location_address(symbol.section, symbol.offset) end
    local resolution = self.names[symbol.name]
    if resolution.kind == "global" or resolution.kind == "weak" then return self:definition_address(resolution)
    elseif resolution.kind == "common" then return resolution.address
    elseif resolution.kind == "script" then return self.script_values[resolution.name]
    elseif resolution.kind == "weakundef" then return 0 end
end
function B:entry_address()
    local entry = self.names[self.script.entry]
    if entry then
        if entry.kind == "global" or entry.kind == "weak" then return self:definition_address(entry)
        elseif entry.kind == "common" then return entry.address end
    end
    return 0
end
local function write_little(bytes, offset, value, width)
    for i = 1, width do bytes[offset + i], value = value % 256, value // 256 end
end
function B:apply_relocations()
    local gp = self.script_values._gp or 0
    for _, output in ipairs(self.script.outputs) do
        for _, section in ipairs(output.components) do
            if section.kind == "input" then
                for i, relocation in ipairs(section.relocations) do
                    relocation.place = section.address + relocation.offset
                    relocation.unpaired = Relocator.unpaired(section.relocations, i)
                    relocation.symbol_value = self:symbol_value(relocation.symbol)
                    if relocation.symbol_value == nil then relocation.status = "undefined"
                    else
                        relocation.status = "ok"
                        if self.far_calls[relocation] then
                            relocation.symbol_value, relocation.status = self.veneers[output][relocation.symbol.name].address, "veneer"
                        end
                        local within
                        relocation.value, relocation.field, within = Relocator.calculate(relocation.type, relocation.symbol_value, relocation.addend, relocation.place, gp)
                        if not within then relocation.status = "overflow" end
                        write_little(section.contents, relocation.offset, relocation.field, Relocator.widths[relocation.type])
                    end
                    local counts = self.relocation_counts[relocation.type]
                    counts[relocation.status], counts.total = counts[relocation.status] + 1, counts.total + 1
                    self.applied[#self.applied + 1] = relocation
                end
            end
        end
    end
end
function B:build_images()
    for _, segment in ipairs(self.script.segments) do
        for i = 1, segment.filesz do segment.image[i] = segment.fill end
        for _, output in ipairs(segment.outputs) do
            if not output.nobits then
                for _, component in ipairs(output.components) do
                    local contents = component.contents
                    if component.kind == "veneer" then
                        contents = { 4, 240, 31, 229 }
                        write_little(contents, 4, self:definition_address(self.names[component.name]), 4)
                    end
                    local offset = component.address - segment.base
                    for i = 1, component.size do segment.image[offset + i] = contents[i] end
                end
            end
        end
    end
    if self.script.checksum then
        local segment = self.script.segment_names[self.script.checksum[1]]
        local offset = self:definition_address(self.names[self.script.checksum[2]]) - segment.base
        write_little(segment.image, offset, 0, 4)
        local total = 0
        for start = 0, segment.filesz - 1, 4 do
            local value = 0
            for i = 0, 3 do value = value + (segment.image[start + i + 1] or 0) * (1 << (8 * i)) end
            total = total + value
        end
        write_little(segment.image, offset, (-total) % 4294967296, 4)
    end
end
function B:symbol_rows()
    local rows = {}
    for _, name in ipairs(self.ordered_names) do
        local resolution = self.names[name]
        if (resolution.kind == "global" or resolution.kind == "weak") and resolution.definition.section.live then
            rows[#rows + 1] = { self:definition_address(resolution), name, resolution.kind, resolution.definer }
        elseif resolution.kind == "common" and resolution.live then rows[#rows + 1] = { resolution.address, name, "common", resolution.definer }
        elseif resolution.kind == "script" then rows[#rows + 1] = { self.script_values[name], name, "script", "*script*" } end
    end
    for _, output in ipairs(self.script.outputs) do
        for _, component in ipairs(output.components) do
            if component.kind == "veneer" then rows[#rows + 1] = { component.address, "__veneer_" .. component.name, "veneer", "*linker*" } end
        end
    end
    table.sort(rows, function(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end)
    return rows
end
local function relocation_location(relocation)
    return relocation.section.owner.name .. " " .. relocation.section.name .. "+" .. relocation.offset
end
function B:diagnostics()
    local lines = {}
    for _, name in ipairs(keys(self.orphans)) do lines[#lines + 1] = string.format("warning: orphan section %s discarded from %d object(s)", name, self.orphans[name]) end
    for _, name in ipairs(self.ordered_names) do
        local resolution = self.names[name]
        if #resolution.strong_definers >= 2 then lines[#lines + 1] = "error: multiple definition of " .. name .. ": " .. table.concat(resolution.strong_definers, " ") end
        if #resolution.commons > 0 and (resolution.kind == "global" or resolution.kind == "script") then
            lines[#lines + 1] = "warning: common symbol " .. name .. " overridden by " .. resolution.definer
        end
        local pairs_set, count = {}, 0
        for _, entry in ipairs(resolution.commons) do
            local key = entry.size .. ":" .. entry.alignment
            if not pairs_set[key] then pairs_set[key], count = true, count + 1 end
        end
        if resolution.kind == "common" and count >= 2 then
            lines[#lines + 1] = string.format("warning: common symbol %s merged to size %d align %d", name, resolution.size, resolution.alignment)
        end
    end
    local entry = self.names[self.script.entry]
    if not entry or entry.kind == "undefined" or entry.kind == "weakundef" then lines[#lines + 1] = "error: entry symbol " .. self.script.entry .. " is undefined" end
    for _, name in ipairs(self.ordered_names) do
        local resolution = self.names[name]
        if resolution.kind == "undefined" and #resolution.unresolved_referrers > 0 then
            lines[#lines + 1] = "error: undefined symbol " .. name .. " referenced by " .. table.concat(resolution.unresolved_referrers, " ")
        end
    end
    for _, segment in ipairs(self.script.segments) do
        if segment.used > segment.length then lines[#lines + 1] = string.format("error: segment %s overflows its length by %d bytes", segment.name, segment.used - segment.length) end
    end
    for i, first in ipairs(self.script.segments) do
        for j = i + 1, #self.script.segments do
            local second = self.script.segments[j]
            if first.memsz >= 1 and second.memsz >= 1 and first.base < second.base + second.memsz and second.base < first.base + first.memsz then
                lines[#lines + 1] = "error: segments " .. first.name .. " and " .. second.name .. " overlap"
            end
        end
    end
    for _, relocation in ipairs(self.applied) do
        local location = relocation_location(relocation)
        if relocation.unpaired then lines[#lines + 1] = "error: unpaired HI16 at " .. location .. " against " .. relocation.symbol.name end
        if relocation.status == "overflow" then
            lines[#lines + 1] = string.format("error: relocation overflow at %s: %s value %d against %s", location, relocation.type, relocation.value, relocation.symbol.name)
        end
    end
    local errors, warnings = 0, 0
    for _, line in ipairs(lines) do
        if line:sub(1, 6) == "error:" then errors = errors + 1 elseif line:sub(1, 8) == "warning:" then warnings = warnings + 1 end
    end
    lines[#lines + 1] = "errors " .. errors .. " warnings " .. warnings
    return lines
end
local function segment_heading(segment)
    return string.format("segment %s vaddr %08x paddr %08x filesz %d memsz %d", segment.name, segment.base, segment.paddr, segment.filesz, segment.memsz)
end
local function image_dump(linker)
    local lines = { string.format("entry %08x %s", linker:entry_address(), linker.script.entry) }
    for _, segment in ipairs(linker.script.segments) do
        lines[#lines + 1] = segment_heading(segment)
        for start = 0, segment.filesz - 1, 16 do
            local bytes = {}
            for i = start + 1, math.min(start + 16, segment.filesz) do bytes[#bytes + 1] = string.format("%02x", segment.image[i]) end
            lines[#lines + 1] = string.format("%08x ", segment.base + start) .. table.concat(bytes, " ")
        end
    end
    return lines
end
local function hex_record(kind, address, data)
    local record = { #data, address // 256, address % 256, kind }
    append(record, data)
    local total = 0
    for _, byte in ipairs(record) do total = total + byte end
    record[#record + 1] = (-total) % 256
    local hex = {}
    for _, byte in ipairs(record) do hex[#hex + 1] = string.format("%02X", byte) end
    return ":" .. table.concat(hex)
end
local function intel_hex(linker)
    local segments, lines, upper = { table.unpack(linker.script.segments) }, {}, 0
    table.sort(segments, function(a, b) return a.paddr < b.paddr or (a.paddr == b.paddr and a.order < b.order) end)
    for _, segment in ipairs(segments) do
        local start = 0
        while start < segment.filesz do
            local address = segment.paddr + start
            local count = math.min(16, segment.filesz - start, 65536 - address % 65536)
            if address // 65536 ~= upper then
                upper = address // 65536
                lines[#lines + 1] = hex_record(4, 0, { upper // 256, upper % 256 })
            end
            local data = {}
            for i = start + 1, start + count do data[#data + 1] = segment.image[i] end
            lines[#lines + 1] = hex_record(0, address % 65536, data)
            start = start + count
        end
    end
    local entry, data = linker:entry_address(), {}
    for i = 3, 0, -1 do data[#data + 1] = (entry >> (i * 8)) % 256 end
    lines[#lines + 1], lines[#lines + 2] = hex_record(5, 0, data), hex_record(1, 0, {})
    return lines
end
local function component_line(component)
    if component.kind == "input" then return string.format("input %08x %d %d %s %s", component.address, component.size, component.alignment, component.owner.name, component.name)
    elseif component.kind == "merged" then return string.format("merged %08x %d sections %d strings %d unique %d saved %d", component.address, component.size, #component.sections, component.strings, component.unique, component.saved)
    elseif component.kind == "common" then return string.format("common %08x %d %d %s %s", component.address, component.size, component.alignment, component.definer, component.name) end
    return string.format("veneer %08x 8 %s", component.address, component.name)
end
local function link_map(linker)
    local lines = {}
    for _, record in ipairs(linker.extractions) do lines[#lines + 1] = "member " .. table.concat(record, " ") end
    for _, signature in ipairs(linker.comdat_order) do
        local group = linker.comdats[signature]
        lines[#lines + 1] = "comdat " .. signature .. " " .. group.keeper .. " " .. (#group.discarded > 0 and table.concat(group.discarded, ",") or "-")
    end
    for _, segment in ipairs(linker.script.segments) do
        lines[#lines + 1] = segment_heading(segment) .. string.format(" used %d length %d %d%%", segment.used, segment.length, 100 * segment.used // segment.length)
        for _, output in ipairs(segment.outputs) do
            lines[#lines + 1] = string.format("section %s %08x %d %d", output.name, output.address, output.size, output.alignment)
            for _, component in ipairs(output.components) do lines[#lines + 1] = component_line(component) end
        end
    end
    for _, object in ipairs(linker.objects) do
        for _, section in ipairs(object.sections) do
            if section.discard_reason then lines[#lines + 1] = string.format("discard %s %s %d %s", object.name, section.name, section.size, section.discard_reason) end
        end
    end
    for _, common in ipairs(linker.commons) do
        if not common.live then lines[#lines + 1] = string.format("discard %s COMMON(%s) %d gc", common.definer, common.name, common.size) end
    end
    for _, row in ipairs(linker:symbol_rows()) do lines[#lines + 1] = string.format("symbol %08x %s %s %s", row[1], row[2], row[3], row[4]) end
    return lines
end
local function cross_references(linker)
    local lines = {}
    for _, name in ipairs(linker.ordered_names) do
        local resolution, status = linker.names[name], "-"
        if resolution.kind == "global" or resolution.kind == "weak" then status = resolution.definition.section.live and "kept" or "discarded"
        elseif resolution.kind == "common" then status = resolution.live and "kept" or "discarded"
        elseif resolution.kind == "script" then status = "kept" end
        lines[#lines + 1] = string.format("%s %s %s %s %s", name, resolution.kind, status, resolution.definer,
            #resolution.referrers > 0 and table.concat(resolution.referrers, ",") or "-")
    end
    return lines
end
local function relocation_report(linker)
    local lines = {}
    for _, relocation in ipairs(linker.applied) do
        local prefix = string.format("%08x %s %s %s %d", relocation.place, relocation_location(relocation), relocation.type, relocation.symbol.name, relocation.addend)
        local values = "- - -"
        if relocation.status ~= "undefined" then
            values = string.format("%08x %d %0" .. Relocator.widths[relocation.type] * 2 .. "x", relocation.symbol_value, relocation.value, relocation.field)
        end
        lines[#lines + 1] = prefix .. " " .. values .. " " .. relocation.status
    end
    for _, kind in ipairs(Relocator.types) do
        local counts = linker.relocation_counts[kind]
        lines[#lines + 1] = string.format("summary %s total %d ok %d veneer %d overflow %d undefined %d", kind, counts.total, counts.ok, counts.veneer, counts.overflow, counts.undefined)
    end
    return lines
end
local linker = B.new(read_script())
linker:load_inputs()
linker:assign_outputs()
linker:collect_garbage()
linker:perform_layout()
linker:load_addresses()
linker:evaluate_defines()
linker:apply_relocations()
linker:build_images()
for _, entry in ipairs({ { "image.hex", image_dump(linker) }, { "flash.ihex", intel_hex(linker) }, { "link.map", link_map(linker) },
    { "xref.txt", cross_references(linker) }, { "relocations.txt", relocation_report(linker) }, { "diagnostics.txt", linker:diagnostics() } }) do
    local output = assert(io.open("output/" .. entry[1], "w"))
    for _, line in ipairs(entry[2]) do output:write(line, "\n") end
    output:close()
end
