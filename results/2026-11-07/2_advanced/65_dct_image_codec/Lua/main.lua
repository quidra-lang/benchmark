local IO = require("image_io")
local Color = require("color")
local DCT = require("dct")
local Entropy = require("entropy")
local Bits = require("bitstream")
local component_names = { "Y", "Cb", "Cr" }
local function append(a, b) for _, value in ipairs(b) do a[#a + 1] = value end end
local function map(values, fn) local result = {}; for i, value in ipairs(values) do result[i] = fn(value, i) end; return result end
local function zeros(size) local result = {}; for i = 1, size do result[i] = 0 end; return result end
local function slice(values, first, last) local result = {}; for i = first, last do result[#result + 1] = values[i] end; return result end
local function sum(values) local result = 0; for _, value in ipairs(values) do result = result + value end; return result end
local function keys(values) local result = {}; for key in pairs(values) do result[#result + 1] = key end; table.sort(result); return result end
local function standard_components(h, v)
    return { { identifier = 1, h = h, v = v, tq = 0, td = 0, ta = 0 }, { identifier = 2, h = 1, v = 1, tq = 1, td = 1, ta = 1 }, { identifier = 3, h = 1, v = 1, tq = 1, td = 1, ta = 1 } }
end
local function layout(width, height, components, restart)
    local result = { width = width, height = height, components = components, restart = restart, factors = {}, blocks = {}, intervals = {}, hmax = 1, vmax = 1, blocks_per_mcu = 0 }
    for i, component in ipairs(components) do
        result.hmax, result.vmax = math.max(result.hmax, component.h), math.max(result.vmax, component.v)
        result.factors[i], result.blocks_per_mcu = { component.h, component.v }, result.blocks_per_mcu + component.h * component.v
    end
    result.mx, result.my = (width + 8 * result.hmax - 1) // (8 * result.hmax), (height + 8 * result.vmax - 1) // (8 * result.vmax)
    result.mcus = result.mx * result.my
    for mcu = 0, result.mcus - 1 do
        for k, component in ipairs(components) do
            for v = 0, component.v - 1 do
                for h = 0, component.h - 1 do result.blocks[#result.blocks + 1] = { mcu = mcu, component = k, bx = component.h * (mcu % result.mx) + h, by = component.v * (mcu // result.mx) + v } end
            end
        end
    end
    local step = restart > 0 and restart or result.mcus
    for first = 0, result.mcus - 1, step do result.intervals[#result.intervals + 1] = { first, math.min(step, result.mcus - first) } end
    return result
end
local function block_range(layout_value, interval)
    local first, count = table.unpack(layout_value.intervals[interval])
    return first * layout_value.blocks_per_mcu + 1, (first + count) * layout_value.blocks_per_mcu
end
local function word(value) return { value // 256, value % 256 } end
local function read_word(data, offset) return 256 * data[offset + 1] + data[offset + 2] end
local function segment(marker, contents)
    local result = { 255, marker }
    append(result, word(#contents + 2)); append(result, contents)
    return result
end
local function read_symbol(reader, table_value)
    local code = 0
    for length = 1, 16 do
        code = 2 * code + reader:bit()
        local symbol = table_value.decode[length][code]
        if symbol ~= nil then return symbol end
    end
    Bits.fail("code")
end
local function decode_block(reader, index, component, tables, predictors)
    local coefficients = zeros(64)
    local size = read_symbol(reader, tables[Entropy.key(0, component.td)])
    local difference = Entropy.amplitude(reader:read(size), size)
    predictors[index] = predictors[index] + difference
    coefficients[1] = predictors[index]
    local position = 1
    while position <= 63 do
        local symbol = read_symbol(reader, tables[Entropy.key(1, component.ta)])
        if symbol == 0 then break end
        local run, count = symbol // 16, symbol % 16
        position = position + run
        if position > 63 then Bits.fail("index") end
        if count > 0 then coefficients[position + 1] = Entropy.amplitude(reader:read(count), count) end
        position = position + 1
    end
    return coefficients
end
local C = {}
C.__index = C
function C.new(transform, basic, standard) return setmetatable({ transform = transform, basic = basic, standard = standard }, C) end
function C:prepare(image, quality, sampling, restart)
    local factor = ({ ["444"] = { 1, 1 }, ["422"] = { 2, 1 }, ["420"] = { 2, 2 } })[sampling]
    local meta = layout(#image[1], #image, standard_components(factor[1], factor[2]), restart)
    local planes = Color.component_planes(Color.split_planes(image), meta.factors, meta.mx, meta.my)
    local quantization, coefficients = DCT.quantization(self.basic, quality), {}
    for number, block in ipairs(meta.blocks) do
        local plane, pixels = planes[block.component], {}
        for y = 0, 7 do pixels[y + 1] = slice(plane[8 * block.by + y + 1], 8 * block.bx + 1, 8 * block.bx + 8) end
        local transformed = DCT.forward(pixels, self.transform)
        coefficients[number] = DCT.zigzag(DCT.quantize(transformed, quantization[meta.components[block.component].tq]))
    end
    return { layout = meta, planes = planes, quantization = quantization, coefficients = coefficients }
end
function C:build_symbols(prepared)
    local meta, frequencies, blocks, differences = prepared.layout, {}, {}, {}
    for _, key in ipairs(Entropy.table_keys) do frequencies[key] = {}; for symbol = 0, 255 do frequencies[key][symbol] = 0 end end
    for interval = 1, #meta.intervals do
        local predictors = zeros(3)
        local first, last = block_range(meta, interval)
        for number = first, last do
            local block, sequence = meta.blocks[number], prepared.coefficients[number]
            local component = meta.components[block.component]
            local difference = sequence[1] - predictors[block.component]
            predictors[block.component], differences[number] = sequence[1], difference
            local bits, size = Entropy.extra_bits(difference)
            local symbols = { { table = Entropy.key(0, component.td), value = size, extra = bits, width = size } }
            local ac_table, run = Entropy.key(1, component.ta), 0
            for i = 2, 64 do
                local value = sequence[i]
                if value == 0 then run = run + 1
                else
                    while run >= 16 do symbols[#symbols + 1] = { table = ac_table, value = 240, extra = 0, width = 0 }; run = run - 16 end
                    bits, size = Entropy.extra_bits(value)
                    symbols[#symbols + 1] = { table = ac_table, value = 16 * run + size, extra = bits, width = size }
                    run = 0
                end
            end
            if run > 0 then symbols[#symbols + 1] = { table = ac_table, value = 0, extra = 0, width = 0 } end
            for _, symbol in ipairs(symbols) do local freq = frequencies[symbol.table]; freq[symbol.value] = freq[symbol.value] + 1 end
            blocks[number] = symbols
        end
    end
    return blocks, differences, frequencies
end
function C:header(meta, quantization, tables)
    local header, contents = { 255, 216 }, {}
    for id = 0, 1 do contents[#contents + 1] = id; append(contents, DCT.zigzag(quantization[id])) end
    append(header, segment(219, contents))
    contents = { 8 }
    append(contents, word(meta.height)); append(contents, word(meta.width)); contents[#contents + 1] = 3
    for _, component in ipairs(meta.components) do append(contents, { component.identifier, 16 * component.h + component.v, component.tq }) end
    append(header, segment(192, contents))
    contents = {}
    for _, key in ipairs(Entropy.table_keys) do
        local table_value = tables[key]
        contents[#contents + 1] = 16 * (key // 4) + key % 4
        append(contents, table_value.counts); append(contents, table_value.symbols)
    end
    append(header, segment(196, contents))
    if meta.restart > 0 then append(header, segment(221, word(meta.restart))) end
    contents = { 3 }
    for _, component in ipairs(meta.components) do append(contents, { component.identifier, 16 * component.td + component.ta }) end
    append(contents, { 0, 63, 0 }); append(header, segment(218, contents))
    return header
end
function C:encode_prepared(prepared, mode)
    local symbols, differences, frequencies = self:build_symbols(prepared)
    local tables = self.standard
    if mode == "optimized" then tables = {}; for _, key in ipairs(Entropy.table_keys) do tables[key] = Entropy.optimized(frequencies[key]) end end
    local header, writer = self:header(prepared.layout, prepared.quantization, tables), Bits.writer()
    local block_bits, intervals = zeros(#prepared.coefficients), {}
    for interval, period in ipairs(prepared.layout.intervals) do
        if interval > 1 then writer:restart(interval - 2) end
        local start = #writer.data
        local first, last = block_range(prepared.layout, interval)
        for number = first, last do
            for _, symbol in ipairs(symbols[number]) do
                local length, code = table.unpack(tables[symbol.table].codes[symbol.value])
                writer:write(code, length); writer:write(symbol.extra, symbol.width)
                block_bits[number] = block_bits[number] + length + symbol.width
            end
        end
        writer:pad()
        intervals[interval] = { period[1], period[2], #header + start, #writer.data - start }
    end
    local data = {}
    append(data, header); append(data, writer.data); append(data, { 255, 217 })
    return { layout = prepared.layout, planes = prepared.planes, quantization = prepared.quantization, coefficients = prepared.coefficients,
        tables = tables, frequencies = frequencies, differences = differences, block_bits = block_bits, intervals = intervals, data = data,
        header_bytes = #header, scan_bytes = #writer.data, padding_bits = writer.padding_bits, stuffed_bytes = writer.stuffed_bytes }
end
function C:encode(image, quality, sampling, mode, restart) return self:encode_prepared(self:prepare(image, quality, sampling, restart), mode) end
function C:parse_header(data)
    local position, segments, quantization, tables, restart = 2, { { 0, "SOI", 0 } }, {}, {}, 0
    local names = { [192] = "SOF0", [196] = "DHT", [219] = "DQT", [221] = "DRI", [218] = "SOS", [254] = "COM" }
    local width, height, components
    while true do
        local marker = data[position + 2]
        local length = read_word(data, position + 2)
        local contents = slice(data, position + 5, position + length + 2)
        local name = marker >= 224 and marker <= 239 and "APP" .. (marker - 224) or names[marker]
        segments[#segments + 1] = { position, name, length }
        position = position + length + 2
        if marker == 219 then
            for offset = 1, #contents, 65 do quantization[contents[offset]] = DCT.unzigzag(slice(contents, offset + 1, offset + 64)) end
        elseif marker == 196 then
            local offset = 1
            while offset <= #contents do
                local class, id = contents[offset] // 16, contents[offset] % 16
                local counts = slice(contents, offset + 1, offset + 16)
                local n = sum(counts)
                tables[Entropy.key(class, id)] = Entropy.table(counts, slice(contents, offset + 17, offset + 16 + n))
                offset = offset + 17 + n
            end
        elseif marker == 192 then
            height, width, components = read_word(contents, 1), read_word(contents, 3), {}
            for i = 1, 3 do
                local offset = 7 + 3 * (i - 1)
                components[i] = { identifier = contents[offset], h = contents[offset + 1] // 16, v = contents[offset + 1] % 16, tq = contents[offset + 2], td = 0, ta = 0 }
            end
        elseif marker == 221 then restart = read_word(contents, 0)
        elseif marker == 218 then
            for i = 1, 3 do local value = contents[3 + 2 * (i - 1)]; components[i].td, components[i].ta = value // 16, value % 16 end
            break
        end
    end
    segments[#segments + 1] = { #data - 2, "EOI", 0 }
    return { layout = layout(width, height, components, restart), quantization = quantization, tables = tables, segments = segments, scan_start = position, scan_bytes = #data - 2 - position }
end
function C:decode_intervals(data, parsed)
    local meta, coefficients, states = parsed.layout, {}, {}
    for i = 1, #meta.blocks do coefficients[i] = zeros(64) end
    for i = 1, #meta.intervals do states[i] = { state = "lost" } end
    local reader, interval = Bits.reader(data, parsed.scan_start), 0
    while interval < #meta.intervals do
        local predictors, pending, current_mcu = zeros(3), {}, meta.intervals[interval + 1][1]
        local first, last = block_range(meta, interval + 1)
        local ok, fault = pcall(function()
            for number = first, last do
                local block = meta.blocks[number]
                current_mcu = block.mcu
                pending[#pending + 1] = decode_block(reader, block.component, meta.components[block.component], parsed.tables, predictors)
            end
            reader:discard()
            local expected = interval < #meta.intervals - 1 and 208 + interval % 8 or 217
            if data[reader.position + 1] ~= 255 or data[reader.position + 2] ~= expected then Bits.fail("sync") end
        end)
        if ok then
            for number = first, last do coefficients[number] = pending[number - first + 1] end
            states[interval + 1] = { state = "ok" }
            reader.position, interval = reader.position + 2, interval + 1
        else
            if type(fault) ~= "table" or fault.category ~= "decode" then error(fault, 0) end
            local offset = reader.position
            reader:discard()
            local resync = assert(Bits.find_resync(data, offset))
            states[interval + 1] = { state = "damaged", kind = fault.kind, mcu = current_mcu, offset = offset, resync = resync }
            local marker = data[resync + 2]
            if marker == 217 then break end
            interval = interval + 1 + ((marker - 208 - interval) % 8)
            reader.position = resync + 2
        end
    end
    return coefficients, states
end
function C:reconstruct_component(meta, k, coefficients, quantization, keep)
    local component, plane = meta.components[k], {}
    local width, height = 8 * component.h * meta.mx, 8 * component.v * meta.my
    for y = 1, height do plane[y] = {}; for x = 1, width do plane[y][x] = 128 end end
    for number, block in ipairs(meta.blocks) do
        if block.component == k then
            local pixels = DCT.inverse(DCT.dequantize(coefficients[number], quantization[component.tq], keep), self.transform)
            for y, row in ipairs(pixels) do for x, value in ipairs(row) do plane[8 * block.by + y][8 * block.bx + x] = value end end
        end
    end
    return plane
end
function C:decode(data)
    local parsed = self:parse_header(data)
    parsed.coefficients, parsed.states = self:decode_intervals(data, parsed)
    parsed.planes = {}
    for k = 1, 3 do parsed.planes[k] = self:reconstruct_component(parsed.layout, k, parsed.coefficients, parsed.quantization) end
    parsed.expanded = Color.upsample(parsed.planes, parsed.layout.factors, parsed.layout.width, parsed.layout.height)
    parsed.image = Color.combine(parsed.expanded)
    return parsed
end
function C:repair(decoded)
    local source = decoded.layout
    local first = source.components[1]
    local meta = layout(source.width, source.height, standard_components(first.h, first.v), source.restart)
    local quantization = { [0] = decoded.quantization[first.tq], [1] = decoded.quantization[source.components[2].tq] }
    return self:encode_prepared({ layout = meta, quantization = quantization, coefficients = decoded.coefficients }, "optimized")
end
local function plane_values(plane)
    local values = {}
    for _, row in ipairs(plane) do append(values, row) end
    return values
end
local function image_values(image)
    local values = {}
    for _, row in ipairs(image) do for _, pixel in ipairs(row) do append(values, pixel) end end
    return values
end
local function error_sum(a, b)
    local total = 0
    for i, value in ipairs(a) do local difference = value - b[i]; total = total + difference * difference end
    return total
end
local function psnr_error(error_value, count)
    if error_value == 0 then return "inf" end
    return string.format("%.2f", 10 * math.log(65025 * count / error_value, 10))
end
local function psnr(a, b) return psnr_error(error_sum(a, b), #a) end
local function image_psnr(a, b) return psnr(image_values(a), image_values(b)) end
local function quality_metrics(original, original_planes, decoded)
    local metrics = {}
    for k = 1, 3 do metrics[k] = psnr(plane_values(original_planes[k]), plane_values(decoded.expanded[k])) end
    local a, b = image_values(original), image_values(decoded.image)
    metrics[4] = psnr_error(error_sum(a, b), #a)
    local maximum = 0
    for i, value in ipairs(a) do maximum = math.max(maximum, math.abs(value - b[i])) end
    return metrics, maximum
end
local function bpp(bytes, width, height)
    local numerator, denominator = 8 * bytes, width * height
    local a, b = numerator, denominator
    while b ~= 0 do a, b = b, a % b end
    return (numerator // a) .. "/" .. (denominator // a)
end
local function frequency_sum(values) local total = 0; for symbol = 0, 255 do total = total + values[symbol] end; return total end
local function same_image(a, b)
    if #a ~= #b or #a[1] ~= #b[1] then return false end
    for y, row in ipairs(a) do for x, pixel in ipairs(row) do for k = 1, 3 do if pixel[k] ~= b[y][x][k] then return false end end end end
    return true
end
local function binary(value, width)
    local digits = {}
    for shift = width - 1, 0, -1 do digits[#digits + 1] = tostring((value >> shift) & 1) end
    return table.concat(digits)
end
local X = {}
X.__index = X
function X.new(image, parameters, codec, stream)
    return setmetatable({ image = image, parameters = parameters, codec = codec, stream = stream, width = #image[1], height = #image,
        original_planes = Color.split_planes(image), quality = parameters.qualities[1], sampling = parameters.sampling, mode = parameters.huffman,
        restart = parameters.restart_interval, prepared = {}, encodings = {}, decodings = {} }, X)
end
function X:encoding(quality, sampling, mode)
    sampling, mode = sampling or self.sampling, mode or self.mode
    local prepared_key = quality .. ":" .. sampling
    local key = prepared_key .. ":" .. mode
    if not self.encodings[key] then
        if not self.prepared[prepared_key] then self.prepared[prepared_key] = self.codec:prepare(self.image, quality, sampling, self.restart) end
        self.encodings[key] = self.codec:encode_prepared(self.prepared[prepared_key], mode)
    end
    return self.encodings[key]
end
function X:decoding(quality, sampling)
    sampling = sampling or self.sampling
    local key = quality .. ":" .. sampling
    if not self.decodings[key] then self.decodings[key] = self.codec:decode(self:encoding(quality, sampling).data) end
    return self.decodings[key]
end
function X:rate_distortion()
    local lines = { "quality,bytes_standard,bytes_optimized,bpp,psnr_y,psnr_cb,psnr_cr,psnr_rgb,max_error" }
    for _, quality in ipairs(self.parameters.qualities) do
        local standard, optimized, selected = self:encoding(quality, nil, "standard"), self:encoding(quality, nil, "optimized"), self:encoding(quality)
        local metrics, maximum = quality_metrics(self.image, self.original_planes, self:decoding(quality))
        local row = { quality, #standard.data, #optimized.data, bpp(#selected.data, self.width, self.height) }
        append(row, metrics); row[#row + 1] = maximum
        lines[#lines + 1] = table.concat(row, ",")
    end
    return lines
end
function X:block_statistics(encoded, decoded)
    local lines, errors = { "blocks " .. #encoded.layout.blocks }, {}
    for number, block in ipairs(encoded.layout.blocks) do
        local original, restored, sequence = encoded.planes[block.component], decoded.planes[block.component], encoded.coefficients[number]
        local error_value, nonzero, last = 0, 0, 0
        for y = 8 * block.by + 1, 8 * block.by + 8 do
            for x = 8 * block.bx + 1, 8 * block.bx + 8 do local difference = original[y][x] - restored[y][x]; error_value = error_value + difference * difference end
        end
        for i, value in ipairs(sequence) do if value ~= 0 then last = i - 1; if i > 1 then nonzero = nonzero + 1 end end end
        errors[number] = error_value
        lines[#lines + 1] = string.format("block %d %s %d %d dc %d diff %d nonzero %d last %d bits %d sse %d", number - 1, component_names[block.component], block.bx, block.by,
            sequence[1], encoded.differences[number], nonzero, last, encoded.block_bits[number], error_value)
    end
    return lines, errors
end
function X:huffman_lines(encoded)
    local lines = {}
    for i, key in ipairs(Entropy.table_keys) do
        local table_value, frequencies = encoded.tables[key], encoded.frequencies[key]
        local bits = 0
        for _, symbol in ipairs(table_value.symbols) do bits = bits + frequencies[symbol] * table_value.codes[symbol][1] end
        lines[#lines + 1] = string.format("table %s class %d id %d symbols %d coded %d bits %d", Entropy.table_names[i], key // 4, key % 4, #table_value.symbols, frequency_sum(frequencies), bits)
        lines[#lines + 1] = "counts " .. table.concat(table_value.counts, " ")
        for _, symbol in ipairs(table_value.symbols) do
            local length, code = table.unpack(table_value.codes[symbol])
            lines[#lines + 1] = string.format("symbol %02x length %d code %s count %d", symbol, length, binary(code, length), frequencies[symbol])
        end
    end
    return lines
end
function X:thumbnail(decoded)
    local meta, dc_values, image = decoded.layout, {}, {}
    for number, block in ipairs(meta.blocks) do dc_values[block.component .. ":" .. block.bx .. ":" .. block.by] = decoded.coefficients[number][1] end
    for y = 0, (self.height + 7) // 8 - 1 do
        local row = {}
        for x = 0, (self.width + 7) // 8 - 1 do
            local values = {}
            for k, component in ipairs(meta.components) do
                local bx, by = x * component.h // meta.hmax, y * component.v // meta.vmax
                local dc = dc_values[k .. ":" .. bx .. ":" .. by]
                local divisor = decoded.quantization[component.tq][1][1]
                values[k] = Color.clamp((dc * divisor + 4) // 8 + 128)
            end
            row[x + 1] = Color.to_rgb(values[1], values[2], values[3])
        end
        image[y + 1] = row
    end
    return image
end
function X:reference_report(encoded, decoded, errors)
    local meta = encoded.layout
    local counts = map(meta.components, function(component) return component.h * component.v * meta.mcus end)
    local lines = {
        "image " .. self.width .. " " .. self.height,
        string.format("sampling %s mcu %d %d grid %d %d", self.sampling, 8 * meta.hmax, 8 * meta.vmax, meta.mx, meta.my),
        string.format("padded %d %d", 8 * meta.hmax * meta.mx, 8 * meta.vmax * meta.my), "blocks " .. table.concat(counts, " "),
        string.format("restart_interval %d markers %d", self.restart, #meta.intervals - 1), "huffman " .. self.mode, "quality " .. self.quality
    }
    for id = 0, 1 do lines[#lines + 1] = "quant " .. id .. " " .. table.concat(DCT.zigzag(encoded.quantization[id]), " ") end
    lines[#lines + 1] = "symbols " .. table.concat(map(Entropy.table_keys, function(key) return frequency_sum(encoded.frequencies[key]) end), " ")
    local ac0, ac1 = encoded.frequencies[Entropy.key(1, 0)], encoded.frequencies[Entropy.key(1, 1)]
    lines[#lines + 1] = "eob " .. (ac0[0] + ac1[0]) .. " zrl " .. (ac0[240] + ac1[240])
    local zero_ac, nonzero = 0, zeros(64)
    for _, sequence in ipairs(encoded.coefficients) do
        local any = false
        for i, value in ipairs(sequence) do if value ~= 0 then nonzero[i] = nonzero[i] + 1; if i > 1 then any = true end end end
        if not any then zero_ac = zero_ac + 1 end
    end
    lines[#lines + 1] = "zero_ac_blocks " .. zero_ac
    lines[#lines + 1] = "nonzero " .. table.concat(nonzero, " ")
    for k, name in ipairs(component_names) do
        local bits, count, error_value = 0, 0, 0
        for number, block in ipairs(meta.blocks) do
            if block.component == k then
                bits, error_value = bits + encoded.block_bits[number], error_value + errors[number]
                for _, value in ipairs(encoded.coefficients[number]) do if value ~= 0 then count = count + 1 end end
            end
        end
        lines[#lines + 1] = string.format("component %s bits %d nonzero %d sse %d", name, bits, count, error_value)
    end
    append(lines, { "padding_bits " .. encoded.padding_bits, "stuffed_bytes " .. encoded.stuffed_bytes, "header_bytes " .. encoded.header_bytes,
        "scan_bytes " .. encoded.scan_bytes, "total_bytes " .. #encoded.data })
    for i, interval in ipairs(encoded.intervals) do lines[#lines + 1] = "interval " .. (i - 1) .. " " .. table.concat(interval, " ") end
    local histogram, first, second = zeros(8), image_values(self.image), image_values(decoded.image)
    local edges = { 1, 2, 4, 8, 16, 32, 64 }
    for i, value in ipairs(first) do
        local error_value, bin = math.abs(value - second[i]), 1
        while bin <= #edges and error_value >= edges[bin] do bin = bin + 1 end
        histogram[bin] = histogram[bin] + 1
    end
    lines[#lines + 1] = "error_histogram " .. table.concat(histogram, " ")
    for _, keep in ipairs(self.parameters.truncate) do
        local plane = self.codec:reconstruct_component(decoded.layout, 1, decoded.coefficients, decoded.quantization, keep)
        local cropped = {}
        for y = 1, self.height do cropped[y] = slice(plane[y], 1, self.width) end
        lines[#lines + 1] = "truncate " .. keep .. " " .. psnr(plane_values(self.original_planes[1]), plane_values(cropped))
    end
    return lines
end
function X:sampling_comparison()
    local lines = {}
    for _, sampling in ipairs({ "444", "422", "420" }) do
        local encoded = self:encoding(self.quality, sampling)
        local metrics = quality_metrics(self.image, self.original_planes, self:decoding(self.quality, sampling))
        lines[#lines + 1] = "sampling_compare " .. sampling .. " " .. #encoded.data .. " " .. table.concat(metrics, " ", 2, 4)
    end
    return lines
end
function X:generations(reference, reference_decoded)
    local lines, previous = {}, self.image
    for generation = 1, self.parameters.generations do
        local encoded, decoded
        if generation == 1 then encoded, decoded = reference, reference_decoded
        else encoded = self.codec:encode(previous, self.quality, self.sampling, self.mode, self.restart); decoded = self.codec:decode(encoded.data) end
        local changed = 0
        for y, row in ipairs(previous) do
            for x, pixel in ipairs(row) do
                local next_pixel = decoded.image[y][x]
                if pixel[1] ~= next_pixel[1] or pixel[2] ~= next_pixel[2] or pixel[3] ~= next_pixel[3] then changed = changed + 1 end
            end
        end
        lines[#lines + 1] = string.format("generation %d %d %s %d", generation, #encoded.data, image_psnr(self.image, decoded.image), changed)
        previous = decoded.image
    end
    return lines
end
function X:quality_search()
    local target, lo, hi, lines = self.parameters.target_bytes, 1, 100, {}
    while lo < hi do
        local mid = (lo + hi + 1) // 2
        local bytes = #self:encoding(mid).data
        lines[#lines + 1] = "rate_control_step " .. mid .. " " .. bytes
        if bytes <= target then lo = mid else hi = mid - 1 end
    end
    local bytes = #self:encoding(lo).data
    lines[#lines + 1] = string.format("rate_control %d %d %s %s", lo, bytes, bytes <= target and "yes" or "no", image_psnr(self.image, self:decoding(lo).image))
    return lines
end
function X:stream_report(decoded, repaired, repaired_decoded)
    local lines, meta = {}, decoded.layout
    for _, segment_value in ipairs(decoded.segments) do lines[#lines + 1] = "stream_segment " .. table.concat(segment_value, " ") end
    lines[#lines + 1] = "stream_image " .. meta.width .. " " .. meta.height
    for _, component in ipairs(meta.components) do
        lines[#lines + 1] = string.format("stream_component %d %d %d %d %d %d", component.identifier, component.h, component.v, component.tq, component.td, component.ta)
    end
    for _, id in ipairs(keys(decoded.quantization)) do lines[#lines + 1] = "stream_quant " .. id .. " " .. table.concat(DCT.zigzag(decoded.quantization[id]), " ") end
    for _, key in ipairs(keys(decoded.tables)) do
        local table_value, longest = decoded.tables[key], 0
        for length, count in ipairs(table_value.counts) do if count > 0 then longest = length end end
        lines[#lines + 1] = string.format("stream_huffman %d %d symbols %d longest %d", key // 4, key % 4, #table_value.symbols, longest)
    end
    local counts = { ok = 0, damaged = 0, lost = 0 }
    for _, result in ipairs(decoded.states) do counts[result.state] = counts[result.state] + 1 end
    lines[#lines + 1] = string.format("stream_restart %d intervals %d ok %d damaged %d lost %d", meta.restart, #meta.intervals, counts.ok, counts.damaged, counts.lost)
    for i, interval in ipairs(meta.intervals) do
        local result = decoded.states[i]
        local state = result.state
        if state == "damaged" then state = state .. " " .. result.kind .. " mcu " .. result.mcu .. " offset " .. result.offset .. " resync " .. result.resync end
        lines[#lines + 1] = string.format("stream_interval %d %d %d %s", i - 1, interval[1], interval[2], state)
    end
    lines[#lines + 1] = "stream_scan_bytes " .. decoded.scan_bytes
    lines[#lines + 1] = string.format("repair %d %d %d identical %s", #repaired.data, repaired.header_bytes, repaired.scan_bytes, same_image(decoded.image, repaired_decoded.image) and "yes" or "no")
    return lines
end
local image = IO.read_ppm("input/image.ppm")
local parameters = IO.params("input/params.txt")
local codec = C.new(IO.tables("input/tables.txt"))
local experiment = X.new(image, parameters, codec, IO.read_hex("input/stream.hex"))
local rate_lines = experiment:rate_distortion()
local reference, decoded = experiment:encoding(experiment.quality), experiment:decoding(experiment.quality)
local block_lines, errors = experiment:block_statistics(reference, decoded)
local report = experiment:reference_report(reference, decoded, errors)
append(report, experiment:sampling_comparison()); append(report, experiment:generations(reference, decoded)); append(report, experiment:quality_search())
local stream_decoded = codec:decode(experiment.stream)
local repaired = codec:repair(stream_decoded)
local repaired_decoded = codec:decode(repaired.data)
append(report, experiment:stream_report(stream_decoded, repaired, repaired_decoded))
local function write(path, lines)
    local output = assert(io.open(path, "w"))
    for _, line in ipairs(lines) do output:write(line, "\n") end
    output:close()
end
write("output/rate_distortion.csv", rate_lines)
IO.write_ppm("output/decoded.ppm", decoded.image)
IO.write_hex("output/bitstream.hex", reference.data)
IO.write_ppm("output/thumbnail.ppm", experiment:thumbnail(decoded))
write("output/huffman_tables.txt", experiment:huffman_lines(reference))
write("output/blocks.txt", block_lines)
IO.write_ppm("output/stream_decoded.ppm", stream_decoded.image)
IO.write_hex("output/repaired.hex", repaired.data)
write("output/report.txt", report)
