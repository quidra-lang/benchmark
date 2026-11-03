local bitstream = require('bitstream')
local rs = require('reed_solomon')
local matrix = require('matrix')
local masking = require('masking')
local render = require('render')
local levels, modes = {'L', 'M', 'Q', 'H'}, {'NUMERIC', 'ALPHANUMERIC', 'BYTE'}
local indicators = {NUMERIC = 1, ALPHANUMERIC = 2, BYTE = 4}
local error_kinds = {'level', 'mode', 'version', 'mask', 'text', 'charset', 'capacity'}
local function append(target, values) for _, value in ipairs(values) do target[#target + 1] = value end end
local function sum(values) local total = 0; for _, value in ipairs(values) do total = total + value end; return total end
local function copy_matrix(symbol) local copy = {}; for index, row in ipairs(symbol) do copy[index] = {table.unpack(row)} end; return copy end
local function words(line) local fields = {}; for field in line:gmatch('%S+') do fields[#fields + 1] = field end; return fields end
local function cw(mode, version)
    return (version == 10 and {NUMERIC = 12, ALPHANUMERIC = 11, BYTE = 16} or {NUMERIC = 10, ALPHANUMERIC = 9, BYTE = 8})[mode]
end
local function dw(mode, count)
    if mode == 'NUMERIC' then return 10 * (count // 3) + ({0, 4, 7})[count % 3 + 1] end
    if mode == 'ALPHANUMERIC' then return 11 * (count // 2) + 6 * (count % 2) end
    return 8 * count
end
local function encodable(mode, character)
    if mode == 'NUMERIC' then return character >= '0' and character <= '9' end
    if mode == 'ALPHANUMERIC' then return bitstream.alphanumeric_values[character] ~= nil end
    local byte = character:byte(); return byte >= 32 and byte <= 126
end
local function all_encodable(mode, text)
    for index = 1, #text do if not encodable(mode, text:sub(index, index)) then return false end end
    return true
end
local function segment_width(mode, count, version) return 4 + cw(mode, version) + dw(mode, count) end
local function mixed_segments(text, version)
    local invalid = {}; for _, mode in ipairs(modes) do invalid[mode] = {[0] = 0} end
    for index = 1, #text do
        for _, mode in ipairs(modes) do invalid[mode][index] = invalid[mode][index - 1] + (encodable(mode, text:sub(index, index)) and 0 or 1) end
    end
    local costs, choices = {[0] = 0}, {}
    for finish = 1, #text do
        local best
        for start = 0, finish - 1 do
            for _, mode in ipairs(modes) do
                if invalid[mode][finish] == invalid[mode][start] then
                    local cost = costs[start] + segment_width(mode, finish - start, version)
                    if best == nil or cost < best then best, choices[finish] = cost, {start = start, mode = mode} end
                end
            end
        end
        costs[finish] = best
    end
    local reverse, segments, finish = {}, {}, #text
    while finish > 0 do
        local choice = choices[finish]
        reverse[#reverse + 1] = {mode = choice.mode, text = text:sub(choice.start + 1, finish)}; finish = choice.start
    end
    for index = #reverse, 1, -1 do segments[#segments + 1] = reverse[index] end
    return {segments = segments, bits = costs[#text]}
end
local function groups(mode, text)
    local result, step = {}, mode == 'NUMERIC' and 3 or mode == 'ALPHANUMERIC' and 2 or 1
    for start = 1, #text, step do
        local characters, value, width = text:sub(start, start + step - 1), nil, nil
        if mode == 'NUMERIC' then value, width = tonumber(characters), ({4, 7, 10})[#characters]
        elseif mode == 'ALPHANUMERIC' then
            value, width = bitstream.alphanumeric_values[characters:sub(1, 1)], 6
            if #characters == 2 then value, width = 45 * value + bitstream.alphanumeric_values[characters:sub(2, 2)], 11 end
        else value, width = characters:byte(), 8 end
        result[#result + 1] = {value = value, width = width, text = characters}
    end
    return result
end
local function assemble_bits(segments, version)
    local writer, trace = bitstream.Writer.new(), {}
    for _, segment in ipairs(segments) do
        local mode, text = segment.mode, segment.text
        local indicator, width = indicators[mode], cw(mode, version)
        writer:write(indicator, 4); writer:write(#text, width)
        trace[#trace + 1] = 'segment ' .. mode .. ' indicator ' .. bitstream.binary(indicator, 4) .. ' count ' .. #text .. ' ' .. bitstream.binary(#text, width)
        for _, group in ipairs(groups(mode, text)) do
            writer:write(group.value, group.width)
            trace[#trace + 1] = 'group ' .. group.value .. ' ' .. bitstream.binary(group.value, group.width) .. ' "' .. group.text .. '"'
        end
    end
    return writer:value(), trace
end
local function pad_bits(bits, capacity)
    local terminator = math.min(4, capacity - #bits)
    local padded = bits .. string.rep('0', terminator)
    local zero_fill = (-#padded) % 8
    padded = padded .. string.rep('0', zero_fill)
    local pad_count, pieces = (capacity - #padded) // 8, {padded}
    for index = 0, pad_count - 1 do pieces[#pieces + 1] = index % 2 == 0 and '11101100' or '00010001' end
    return table.concat(pieces), {terminator, zero_fill, pad_count}
end
local BlockLayout = {}
BlockLayout.__index = BlockLayout
function BlockLayout.new(degree, b1, k1, b2, k2)
    local lengths, placement = {}, {}
    for _ = 1, b1 do lengths[#lengths + 1] = k1 end
    for _ = 1, b2 do lengths[#lengths + 1] = k2 end
    local maximum = 0; for _, length in ipairs(lengths) do maximum = math.max(maximum, length) end
    for position = 1, maximum do for block, length in ipairs(lengths) do if position <= length then placement[#placement + 1] = {block, position} end end end
    for offset = 1, degree do for block, length in ipairs(lengths) do placement[#placement + 1] = {block, length + offset} end end
    local data = sum(lengths)
    return setmetatable({degree = degree, lengths = lengths, count = #lengths, data = data, capacity = 8 * data,
        total = data + degree * #lengths, placement = placement}, BlockLayout)
end
function BlockLayout:encode(data)
    local blocks, start, interleaved = {}, 1, {}
    for _, length in ipairs(self.lengths) do
        local words = {}; for index = start, start + length - 1 do words[#words + 1] = data[index] end
        append(words, rs.parity(words, self.degree)); blocks[#blocks + 1] = words; start = start + length
    end
    for _, position in ipairs(self.placement) do interleaved[#interleaved + 1] = blocks[position[1]][position[2]] end
    return blocks, interleaved
end
function BlockLayout:deinterleave(codewords)
    local blocks = {}
    for block, length in ipairs(self.lengths) do blocks[block] = {}; for index = 1, length + self.degree do blocks[block][index] = 0 end end
    for index, position in ipairs(self.placement) do blocks[position[1]][position[2]] = codewords[index] end
    return blocks
end
local Request = {}
Request.__index = Request
function Request.new(fields, text)
    return setmetatable({identifier = fields[1], level_token = fields[2], mode_token = fields[3], version_token = fields[4],
        mask_token = fields[5], text = text, splits = {}}, Request)
end
function Request:split(version)
    local category = version == 10 and 10 or 1
    if not self.splits[category] then
        if self.mode == 'MIXED' then self.splits[category] = mixed_segments(self.text, version)
        else self.splits[category] = {segments = {{mode = self.mode, text = self.text}}, bits = segment_width(self.mode, #self.text, version)} end
    end
    return self.splits[category]
end
function Request:prepare(codec)
    local valid_level = false
    for _, level in ipairs(levels) do if self.level_token == level or self.level_token == level .. '+' then valid_level = true end end
    if not valid_level then return 'level ' .. self.level_token end
    if self.mode_token ~= 'NUMERIC' and self.mode_token ~= 'ALPHANUMERIC' and self.mode_token ~= 'BYTE' and self.mode_token ~= 'AUTO' and self.mode_token ~= 'MIXED' then return 'mode ' .. self.mode_token end
    local valid_version = self.version_token == 'AUTO'
    for version = 1, 10 do if self.version_token == tostring(version) then valid_version = true end end
    if not valid_version then return 'version ' .. self.version_token end
    local valid_mask = self.mask_token == 'AUTO'
    for mask = 0, 7 do if self.mask_token == tostring(mask) then valid_mask = true end end
    if not valid_mask then return 'mask ' .. self.mask_token end
    if #self.text == 0 then return 'text' end
    if self.mode_token == 'NUMERIC' or self.mode_token == 'ALPHANUMERIC' then
        for position = 1, #self.text do if not encodable(self.mode_token, self.text:sub(position, position)) then return 'charset position ' .. (position - 1) end end
    end
    self.mode = self.mode_token
    if self.mode == 'AUTO' then for _, mode in ipairs(modes) do if all_encodable(mode, self.text) then self.mode = mode; break end end end
    local base, bits, capacity = self.level_token:sub(1, 1), nil, nil
    local first, last = 1, 10
    if self.version_token ~= 'AUTO' then first, last = tonumber(self.version_token), tonumber(self.version_token) end
    for version = first, last do
        bits, capacity = self:split(version).bits, codec:table(version, base).capacity
        if bits <= capacity then self.version = version; break end
    end
    if not self.version then return 'capacity bits ' .. bits .. ' capacity ' .. capacity end
    local selected = self:split(self.version)
    self.segments, self.bit_count, self.level = selected.segments, selected.bits, base
    if self.level_token:sub(-1) == '+' then
        local eligible = false
        for _, level in ipairs(levels) do
            if level == base then eligible = true end
            if eligible and self.bit_count <= codec:table(self.version, level).capacity then self.level = level end
        end
    end
    self.boosted = self.level ~= base
end

local function read_inputs()
    local requests, params, tables, alignments, damage, scans = {}, {}, {}, {}, {}, {}
    for line in io.lines('input/requests.txt') do local header, text = line:match('^(.-):(.*)$'); requests[#requests + 1] = Request.new(words(header), text) end
    for line in io.lines('input/params.txt') do local f = words(line); params[f[1]] = tonumber(f[2]) end
    for line in io.lines('input/tables.txt') do
        local f = words(line); local version = tonumber(f[2])
        if f[1] == 'block' then tables[version .. ':' .. f[3]] = BlockLayout.new(tonumber(f[4]), tonumber(f[5]), tonumber(f[6]), tonumber(f[7]), tonumber(f[8]))
        else local values = {}; for index = 3, #f do values[#values + 1] = tonumber(f[index]) end; alignments[version] = values end
    end
    for line in io.lines('input/damage.txt') do
        local f = words(line); local operation = {kind = f[2]}
        if f[2] == 'flip' then operation.x, operation.y = tonumber(f[3]), tonumber(f[4])
        elseif f[2] == 'fill' then operation.x, operation.y, operation.width, operation.height, operation.color = tonumber(f[3]), tonumber(f[4]), tonumber(f[5]), tonumber(f[6]), f[7] == 'dark' and 1 or 0 end
        damage[f[1]] = damage[f[1]] or {}; damage[f[1]][#damage[f[1]] + 1] = operation
    end
    local lines = {}; for line in io.lines('input/scans.txt') do lines[#lines + 1] = line end
    local index = 1
    while index <= #lines do
        local name, size, symbol = words(lines[index])[2], #lines[index + 1], {}
        for y = 1, size do symbol[y] = {}; for x = 1, size do symbol[y][x] = lines[index + y]:sub(x, x) == '#' and 1 or 0 end end
        scans[#scans + 1] = {name = name, symbol = symbol}; index = index + size + 1
    end
    return requests, params, tables, alignments, damage, scans
end
local function make_encoding(request, codec)
    local geometry, layout = codec:geometry(request.version), codec:table(request.version, request.level)
    local bits, trace = assemble_bits(request.segments, request.version)
    local padded, padding = pad_bits(bits, layout.capacity)
    local blocks, codewords = layout:encode(bitstream.to_codewords(padded))
    local unmasked, stream = copy_matrix(geometry.symbol), bitstream.from_codewords(codewords)
    for index = 1, #stream do local p = geometry.order[index]; unmasked[p[2] + 1][p[1] + 1] = tonumber(stream:sub(index, index)) end
    local candidates, penalties, best = {}, {}, 1
    for mask = 0, 7 do
        local symbol = masking.apply(unmasked, geometry.order, mask)
        for _, positions in ipairs(matrix.format_positions(geometry.size)) do matrix.write_value(symbol, positions, matrix.format_information(request.level, mask)) end
        candidates[mask + 1], penalties[mask + 1] = symbol, masking.penalties(symbol)
        if sum(penalties[mask + 1]) < sum(penalties[best]) then best = mask + 1 end
    end
    local mask = request.mask_token == 'AUTO' and best - 1 or tonumber(request.mask_token)
    local symbol, dark = candidates[mask + 1], 0
    for _, row in ipairs(symbol) do dark = dark + sum(row) end
    return {request = request, layout = geometry, block_layout = layout, trace = trace, padding = padding, blocks = blocks,
        codewords = codewords, penalties = penalties, mask = mask, symbol = symbol, dark = dark}
end

local function rotate(symbol)
    local size, result = #symbol, {}
    for y = 1, size do result[y] = {}; for x = 1, size do result[y][x] = symbol[size + 1 - x][y] end end
    return result
end
local function transpose(symbol)
    local result = {}; for y = 1, #symbol do result[y] = {}; for x = 1, #symbol do result[y][x] = symbol[x][y] end end; return result
end
local function finder_rotation(symbol)
    local size = #symbol
    local corners, best, minimum = {{size - 7, size - 7}, {size - 7, 0}, {0, 0}, {0, size - 7}}, 0, nil
    for index, corner in ipairs(corners) do
        local score = 0
        for y = 0, 6 do for x = 0, 6 do
            local expected = math.max(math.abs(x - 3), math.abs(y - 3)) ~= 2 and 1 or 0
            if symbol[corner[2] + y + 1][corner[1] + x + 1] == expected then score = score + 1 end
        end end
        if minimum == nil or score < minimum then best, minimum = index - 1, score end
    end
    return best
end
local function hamming(first, second)
    local value, count = first ~ second, 0
    while value > 0 do count = count + (value & 1); value = value >> 1 end
    return count
end
local function nearest(candidates, value)
    local chosen, distance
    for _, candidate in ipairs(candidates) do
        local current = hamming(value, candidate.value)
        if distance == nil or current < distance then chosen, distance = candidate, current end
    end
    return chosen, distance
end
local function read_segment(reader, mode, count)
    local text = {}
    while count > 0 do
        local group_size, value
        if mode == 'NUMERIC' then
            group_size = math.min(3, count); value = reader:read(({4, 7, 10})[group_size])
            if value >= ({10, 100, 1000})[group_size] then return nil end
            text[#text + 1] = string.format('%0' .. group_size .. 'd', value)
        elseif mode == 'ALPHANUMERIC' then
            group_size = math.min(2, count); value = reader:read(group_size == 2 and 11 or 6)
            if value >= (group_size == 2 and 2025 or 45) then return nil end
            if group_size == 2 then local index = value // 45 + 1; text[#text + 1] = bitstream.alphanumeric:sub(index, index) end
            local index = value % 45 + 1; text[#text + 1] = bitstream.alphanumeric:sub(index, index)
        else
            group_size, value = 1, reader:read(8)
            if value < 32 or value > 126 then return nil end
            text[#text + 1] = string.char(value)
        end
        count = count - group_size
    end
    return table.concat(text)
end
local function parse_data(attempt, bits, version)
    local reader, text, finish = bitstream.Reader.new(bits), {}, 0
    local mode_by_indicator = {[1] = 'NUMERIC', [2] = 'ALPHANUMERIC', [4] = 'BYTE'}
    while reader:remaining() >= 4 do
        local indicator = reader:read(4)
        if indicator == 0 then break end
        local mode = mode_by_indicator[indicator]
        if not mode then attempt.lines[#attempt.lines + 1] = 'parse failed indicator ' .. bitstream.binary(indicator, 4); return end
        local width = cw(mode, version)
        if reader:remaining() < width then attempt.lines[#attempt.lines + 1] = 'parse failed length ' .. mode; return end
        local count = reader:read(width)
        if reader:remaining() < dw(mode, count) then attempt.lines[#attempt.lines + 1] = 'parse failed length ' .. mode; return end
        local segment = read_segment(reader, mode, count)
        if segment == nil then attempt.lines[#attempt.lines + 1] = 'parse failed value ' .. mode; return end
        text[#text + 1] = segment; attempt.lines[#attempt.lines + 1] = 'segment ' .. mode .. ' ' .. count; finish = reader.position - 1
    end
    local expected = pad_bits(bits:sub(1, finish), #bits)
    attempt.lines[#attempt.lines + 1] = 'padding ' .. (expected == bits and 'ok' or 'bad')
    attempt.text = table.concat(text); attempt.lines[#attempt.lines + 1] = 'text "' .. attempt.text .. '"'
end
local Codec = {}
Codec.__index = Codec
function Codec.new(tables, alignments)
    local formats, versions = {}, {}
    for _, level in ipairs(levels) do for mask = 0, 7 do formats[#formats + 1] = {value = matrix.format_information(level, mask), level = level, mask = mask} end end
    for version = 7, 40 do versions[#versions + 1] = {value = matrix.version_information(version), version = version} end
    return setmetatable({tables = tables, alignments = alignments, geometries = {}, formats = formats, versions = versions}, Codec)
end
function Codec:table(version, level) return self.tables[version .. ':' .. level] end
function Codec:geometry(version)
    if not self.geometries[version] then
        local symbol, areas = matrix.function_matrix(version, self.alignments[version])
        local order, indices, size = matrix.reading_order(areas), {}, #symbol
        for index, p in ipairs(order) do indices[p[2] * size + p[1]] = index - 1 end
        self.geometries[version] = {size = size, symbol = symbol, areas = areas, order = order, indices = indices,
            data_modules = #order, function_modules = size * size - #order}
    end
    return self.geometries[version]
end
function Codec:attempt(symbol)
    local attempt, size = {lines = {}, blocks = {}}, #symbol
    local version = (size - 17) // 4
    local positions = matrix.format_positions(size)
    local first, second = matrix.read_value(symbol, positions[1]), matrix.read_value(symbol, positions[2])
    local nearest_first, d1 = nearest(self.formats, first)
    local nearest_second, d2 = nearest(self.formats, second)
    local prefix = 'format ' .. bitstream.binary(first, 15) .. ' ' .. bitstream.binary(second, 15) .. ' distance ' .. d1 .. ' ' .. d2
    if math.min(d1, d2) > 3 then attempt.lines[#attempt.lines + 1] = prefix .. ' unreadable'; return attempt end
    local chosen = d2 < d1 and nearest_second or nearest_first
    local level, mask = chosen.level, chosen.mask
    attempt.lines[#attempt.lines + 1] = prefix .. ' level ' .. level .. ' mask ' .. mask
    if version >= 7 then
        positions = matrix.version_positions(size)
        first, second = matrix.read_value(symbol, positions[1]), matrix.read_value(symbol, positions[2])
        nearest_first, d1 = nearest(self.versions, first); nearest_second, d2 = nearest(self.versions, second)
        prefix = 'version ' .. bitstream.binary(first, 18) .. ' ' .. bitstream.binary(second, 18) .. ' distance ' .. d1 .. ' ' .. d2
        if math.min(d1, d2) > 3 then attempt.lines[#attempt.lines + 1] = prefix .. ' unreadable'; return attempt end
        chosen = d2 < d1 and nearest_second or nearest_first
        attempt.lines[#attempt.lines + 1] = prefix .. ' decoded ' .. chosen.version
        if chosen.version ~= version then return attempt end
    end
    local geometry, layout = self:geometry(version), self:table(version, level)
    local unmasked, pieces = masking.apply(symbol, geometry.order, mask), {}
    for index = 1, 8 * layout.total do local p = geometry.order[index]; pieces[#pieces + 1] = tostring(unmasked[p[2] + 1][p[1] + 1]) end
    local blocks, corrected_blocks, failed = layout:deinterleave(bitstream.to_codewords(table.concat(pieces))), {}, false
    for block, received in ipairs(blocks) do
        local syndromes, corrected, positions = rs.correct(received, layout.degree)
        local line, status = 'block ' .. (block - 1) .. ' syndromes ' .. bitstream.hexadecimal(syndromes), nil
        if corrected == nil then status, failed = 'failed', true; line = line .. ' failed'
        elseif #positions > 0 then status = 'corrected'; line = line .. ' corrected ' .. table.concat(positions, ' ')
        else status = 'ok'; line = line .. ' ok' end
        attempt.lines[#attempt.lines + 1] = line; attempt.blocks[#attempt.blocks + 1] = {status = status, positions = #positions}
        corrected_blocks[block] = corrected or {}
    end
    if failed then return attempt end
    local data = {}
    for block, words in ipairs(corrected_blocks) do for position = 1, layout.lengths[block] do data[#data + 1] = words[position] end end
    parse_data(attempt, bitstream.from_codewords(data), version)
    return attempt
end
function Codec:decode(symbol)
    local rotations, oriented = finder_rotation(symbol), symbol
    for _ = 1, rotations do oriented = rotate(oriented) end
    local adopted, mirrored = self:attempt(oriented), false
    if adopted.text == nil then
        local second = self:attempt(transpose(oriented))
        if second.text ~= nil then adopted, mirrored = second, true end
    end
    table.insert(adopted.lines, 1, 'orientation rotations ' .. rotations .. ' mirrored ' .. (mirrored and 'yes' or 'no'))
    return adopted
end

local function codes_lines(encoding, codec)
    local request, geometry, layout = encoding.request, encoding.layout, encoding.block_layout
    local version, level, segments = request.version, request.level, {}
    local lines = {'symbol version ' .. version .. ' level ' .. level .. ' mask ' .. encoding.mask .. ' size ' .. geometry.size}
    for _, segment in ipairs(request.segments) do segments[#segments + 1] = segment.mode .. ':' .. #segment.text end
    lines[#lines + 1] = 'segments ' .. #segments .. ' ' .. table.concat(segments, ' ')
    local alternatives = {}
    for _, mode in ipairs(modes) do alternatives[#alternatives + 1] = mode .. ' ' .. (all_encodable(mode, request.text) and tostring(segment_width(mode, #request.text, version)) or '-') end
    alternatives[#alternatives + 1] = 'MIXED ' .. (request.mode == 'MIXED' and request.bit_count or mixed_segments(request.text, version).bits)
    lines[#lines + 1] = 'bits data ' .. request.bit_count .. ' capacity ' .. layout.capacity .. ' alternatives ' .. table.concat(alternatives, ' ')
    local fits = {}
    for _, candidate_level in ipairs(levels) do
        local fitting = '-'
        for candidate = 1, 10 do if request:split(candidate).bits <= codec:table(candidate, candidate_level).capacity then fitting = candidate; break end end
        fits[#fits + 1] = candidate_level .. ' ' .. fitting
    end
    lines[#lines + 1] = 'fits ' .. table.concat(fits, ' ')
    lines[#lines + 1] = 'modules function ' .. geometry.function_modules .. ' data ' .. geometry.data_modules .. ' remainder ' .. (geometry.data_modules - 8 * layout.total) .. ' dark ' .. encoding.dark
    lines[#lines + 1] = 'format ' .. bitstream.binary(matrix.format_information(level, encoding.mask), 15) .. ' version ' .. (version >= 7 and bitstream.binary(matrix.version_information(version), 18) or 'none')
    for index, p in ipairs(encoding.penalties) do lines[#lines + 1] = 'penalty ' .. (index - 1) .. ' n1 ' .. p[1] .. ' n2 ' .. p[2] .. ' n3 ' .. p[3] .. ' n4 ' .. p[4] .. ' total ' .. sum(p) end
    append(lines, render.symbol_lines(encoding.symbol)); return lines
end
local function codeword_lines(encoding)
    local request, layout = encoding.request, encoding.block_layout
    local lines = {'request ' .. request.identifier .. ' version ' .. request.version .. ' level ' .. request.level .. ' blocks ' .. layout.count .. ' data ' .. layout.data .. ' ec_per_block ' .. layout.degree .. ' total ' .. layout.total}
    for block, words in ipairs(encoding.blocks) do
        local data, parity = {}, {}
        for index, value in ipairs(words) do local target = index <= layout.lengths[block] and data or parity; target[#target + 1] = value end
        lines[#lines + 1] = 'block ' .. (block - 1) .. ' data ' .. bitstream.hexadecimal(data)
        lines[#lines + 1] = 'block ' .. (block - 1) .. ' ec ' .. bitstream.hexadecimal(parity)
    end
    lines[#lines + 1] = 'interleaved ' .. bitstream.hexadecimal(encoding.codewords); return lines
end
local function bitstream_lines(encoding)
    local request, p = encoding.request, encoding.padding
    local lines = {'request ' .. request.identifier .. ' version ' .. request.version .. ' bits ' .. request.bit_count .. ' capacity ' .. encoding.block_layout.capacity}
    append(lines, encoding.trace); lines[#lines + 1] = 'terminator ' .. p[1] .. ' zero_fill ' .. p[2] .. ' pad_bytes ' .. p[3]
    return lines
end
local function read_image(path)
    local lines = {}; for line in io.lines(path) do lines[#lines + 1] = line end
    local dimensions = words(lines[2]); local width, height = tonumber(dimensions[1]), tonumber(dimensions[2])
    local pixels, left, right, top = {}, width + 1, 0, height + 1
    for y = 1, height do
        pixels[y] = {}
        for x = 1, width do
            local value = tonumber(lines[y + 2]:sub(x, x)); pixels[y][x] = value
            if value == 1 then left, right, top = math.min(left, x), math.max(right, x), math.min(top, y) end
        end
    end
    local run = 0
    while left + run <= width and pixels[top][left + run] == 1 do run = run + 1 end
    local unit = run // 7
    local size, symbol = (right - left + 1) // unit, {}
    for y = 0, size - 1 do symbol[y + 1] = {}; for x = 0, size - 1 do symbol[y + 1][x + 1] = pixels[top + unit * y][left + unit * x] end end
    local well_formed = true
    for y = 1, height do for x = 1, width do
        local expected = 0
        if left <= x and x < left + unit * size and top <= y and y < top + unit * size then expected = symbol[(y - top) // unit + 1][(x - left) // unit + 1] end
        if pixels[y][x] ~= expected then well_formed = false end
    end end
    return symbol, 'image ' .. width .. ' ' .. height .. ' quiet ' .. ((left - 1) // unit) .. ' scale ' .. unit .. ' size ' .. size .. ' ' .. (well_formed and 'ok' or 'bad')
end
local function damaged_symbol(encoding, operations)
    local symbol = copy_matrix(encoding.symbol)
    for _, operation in ipairs(operations) do
        if operation.kind == 'flip' then symbol[operation.y + 1][operation.x + 1] = symbol[operation.y + 1][operation.x + 1] ~ 1
        elseif operation.kind == 'fill' then for y = operation.y, operation.y + operation.height - 1 do for x = operation.x, operation.x + operation.width - 1 do symbol[y + 1][x + 1] = operation.color end end end
    end
    local counts, damaged_words = {0, 0, 0, 0, 0}, {}
    for block = 1, encoding.block_layout.count do damaged_words[block] = {} end
    for y, row in ipairs(symbol) do for x, value in ipairs(row) do
        if value ~= encoding.symbol[y][x] then
            local area = encoding.layout.areas[y][x]
            if area == matrix.FUNCTION then counts[1] = counts[1] + 1
            elseif area == matrix.FORMAT then counts[2] = counts[2] + 1
            elseif area == matrix.VERSION then counts[3] = counts[3] + 1
            else
                local index = encoding.layout.indices[(y - 1) * encoding.layout.size + x - 1]
                if index < 8 * encoding.block_layout.total then
                    counts[4] = counts[4] + 1
                    local position = encoding.block_layout.placement[index // 8 + 1]; damaged_words[position[1]][position[2]] = true
                else counts[5] = counts[5] + 1 end
            end
        end
    end end
    for _, operation in ipairs(operations) do if operation.kind == 'rotate' then symbol = rotate(symbol) elseif operation.kind == 'mirror' then symbol = transpose(symbol) end end
    local details, errors = {}, {}
    for index, area in ipairs({'function', 'format', 'version', 'data', 'remainder'}) do details[#details + 1] = area .. ' ' .. counts[index] end
    for _, words in ipairs(damaged_words) do local count = 0; for _ in pairs(words) do count = count + 1 end; errors[#errors + 1] = count end
    return symbol, {'check damaged operations ' .. #operations, 'damage changed ' .. sum(counts) .. ' ' .. table.concat(details, ' '),
        'errors ' .. table.concat(errors, ' ') .. ' limit ' .. (encoding.block_layout.degree // 2)}
end
local function tolerance(encoding, codec, color)
    local size = encoding.layout.size
    for side = 1, size do
        local symbol, start = copy_matrix(encoding.symbol), (size - side) // 2
        for y = start, start + side - 1 do for x = start, start + side - 1 do symbol[y + 1][x + 1] = color end end
        if codec:decode(symbol).text ~= encoding.request.text then return side - 1 end
    end
    return size
end
local Summary = {}
Summary.__index = Summary
function Summary.new() return setmetatable({totals = {}}, Summary) end
function Summary:add(key, amount) self.totals[key] = (self.totals[key] or 0) + (amount or 1) end
function Summary:count(key) return self.totals[key] or 0 end
function Summary:record_encoding(encoding)
    local request, layout = encoding.request, encoding.block_layout
    self:add('encoded'); self:add('mode.' .. request.mode); self:add('level.' .. request.level); self:add('boosted', request.boosted and 1 or 0)
    self:add('version.' .. request.version); self:add('mask.' .. encoding.mask); self:add('segments', #request.segments)
    self:add('data', layout.data); self:add('ec', layout.degree * layout.count); self:add('modules', encoding.layout.size * encoding.layout.size); self:add('dark', encoding.dark)
end
function Summary:record_check(attempt, text)
    local result = attempt.text == nil and 'failed' or attempt.text == text and 'ok' or 'mismatch'
    self:add('checks'); self:add('check.' .. result)
    for _, block in ipairs(attempt.blocks) do self:add('block.' .. block.status); self:add('corrected_positions', block.positions) end
    return result
end
function Summary:lines(request_count)
    local errors, error_parts, mode_parts, level_parts, version_parts, mask_parts, check_parts, block_parts = 0, {}, {}, {}, {}, {}, {}, {}
    for _, kind in ipairs(error_kinds) do errors = errors + self:count('error.' .. kind); error_parts[#error_parts + 1] = kind .. ' ' .. self:count('error.' .. kind) end
    for _, mode in ipairs({'NUMERIC', 'ALPHANUMERIC', 'BYTE', 'MIXED'}) do mode_parts[#mode_parts + 1] = mode .. ' ' .. self:count('mode.' .. mode) end
    for _, level in ipairs(levels) do level_parts[#level_parts + 1] = level .. ' ' .. self:count('level.' .. level) end
    for version = 1, 10 do version_parts[#version_parts + 1] = self:count('version.' .. version) end
    for mask = 0, 7 do mask_parts[#mask_parts + 1] = self:count('mask.' .. mask) end
    for _, status in ipairs({'ok', 'mismatch', 'failed'}) do check_parts[#check_parts + 1] = status .. ' ' .. self:count('check.' .. status) end
    for _, status in ipairs({'ok', 'corrected', 'failed'}) do block_parts[#block_parts + 1] = status .. ' ' .. self:count('block.' .. status) end
    return {'requests ' .. request_count .. ' encoded ' .. self:count('encoded') .. ' errors ' .. errors,
        'error_kinds ' .. table.concat(error_parts, ' '), 'modes ' .. table.concat(mode_parts, ' '),
        'levels ' .. table.concat(level_parts, ' ') .. ' boosted ' .. self:count('boosted'), 'versions ' .. table.concat(version_parts, ' '), 'masks ' .. table.concat(mask_parts, ' '),
        'segments ' .. self:count('segments') .. ' data_codewords ' .. self:count('data') .. ' ec_codewords ' .. self:count('ec'),
        'modules ' .. self:count('modules') .. ' dark ' .. self:count('dark'), 'checks ' .. self:count('checks') .. ' ' .. table.concat(check_parts, ' '),
        'blocks ' .. table.concat(block_parts, ' ') .. ' codewords ' .. self:count('corrected_positions'),
        'scans ' .. self:count('scans') .. ' decoded ' .. self:count('scan.decoded') .. ' failed ' .. self:count('scan.failed')}
end
local function check_lines(encoding, codec, params, operations, summary)
    local request, path = encoding.request, 'output/qr_' .. encoding.request.identifier .. '.pbm'
    local file = assert(io.open(path, 'w')); file:write(render.pbm_text(encoding.symbol, params.quiet_zone, params.scale)); file:close()
    local symbol, image_line = read_image(path)
    local lines = {'request ' .. request.identifier, image_line, 'check clean'}
    local attempt = codec:decode(symbol); append(lines, attempt.lines); lines[#lines + 1] = 'result ' .. summary:record_check(attempt, request.text)
    if #operations > 0 then
        local damaged, details = damaged_symbol(encoding, operations); append(lines, details)
        attempt = codec:decode(damaged); append(lines, attempt.lines); lines[#lines + 1] = 'result ' .. summary:record_check(attempt, request.text)
    end
    local light, dark = tolerance(encoding, codec, 0), tolerance(encoding, codec, 1)
    lines[#lines + 1] = 'tolerance light ' .. light .. ' dark ' .. dark
    return lines
end
local function capacity_lines(codec)
    local lines = {}
    for version = 1, 10 do
        local geometry, total, alignment = codec:geometry(version), codec:table(version, 'L').total, codec.alignments[version]
        lines[#lines + 1] = 'version ' .. version .. ' size ' .. geometry.size .. ' data_modules ' .. geometry.data_modules .. ' codewords ' .. total
            .. ' remainder ' .. (geometry.data_modules - 8 * total) .. ' alignment ' .. (#alignment > 0 and table.concat(alignment, ' ') or 'none')
        for _, level in ipairs(levels) do
            local layout, maxima = codec:table(version, level), {}
            for _, mode in ipairs(modes) do
                local count = 0; while segment_width(mode, count + 1, version) <= layout.capacity do count = count + 1 end
                maxima[#maxima + 1] = count
            end
            lines[#lines + 1] = 'level ' .. level .. ' blocks ' .. layout.count .. ' data ' .. layout.data .. ' ec_per_block ' .. layout.degree
                .. ' numeric ' .. maxima[1] .. ' alphanumeric ' .. maxima[2] .. ' byte ' .. maxima[3]
        end
    end
    return lines
end

local requests, params, tables, alignments, damage, scans = read_inputs()
local codec, summary = Codec.new(tables, alignments), Summary.new()
os.execute('mkdir -p output')
local reports = {codes = {}, codewords = {}, bitstream = {}, selfcheck = {}, scans = {}}
for _, request in ipairs(requests) do
    reports.codes[#reports.codes + 1] = 'request ' .. request.identifier
    local failure = request:prepare(codec)
    if failure then reports.codes[#reports.codes + 1] = 'error ' .. failure; summary:add('error.' .. failure:match('^%S+'))
    else
        local encoding = make_encoding(request, codec)
        append(reports.codes, codes_lines(encoding, codec)); append(reports.codewords, codeword_lines(encoding)); append(reports.bitstream, bitstream_lines(encoding))
        summary:record_encoding(encoding); append(reports.selfcheck, check_lines(encoding, codec, params, damage[request.identifier] or {}, summary))
    end
end
for _, scan in ipairs(scans) do
    reports.scans[#reports.scans + 1] = 'scan ' .. scan.name .. ' size ' .. #scan.symbol
    local attempt = codec:decode(scan.symbol); append(reports.scans, attempt.lines)
    local result = attempt.text ~= nil and 'decoded' or 'failed'; reports.scans[#reports.scans + 1] = 'result ' .. result
    summary:add('scans'); summary:add('scan.' .. result)
end
reports.capacity, reports.summary = capacity_lines(codec), summary:lines(#requests)
for name, lines in pairs(reports) do
    local file = assert(io.open('output/' .. name .. '.txt', 'w'))
    file:write(table.concat(lines, '\n'), #lines > 0 and '\n' or ''); file:close()
end
