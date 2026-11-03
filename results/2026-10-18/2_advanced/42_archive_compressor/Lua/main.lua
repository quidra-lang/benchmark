local bitio = require("bitio")
local lzw = require("lzw")
local lz77 = require("lz77")
local huffman = require("huffman")
local arith = require("arith_coder")
local methods = {"STORE", "LZW", "LZ77", "LZH", "ARITH"}
local statuses = {"ok", "repaired", "checksum", "error", "unsupported", "truncated", "bad_header"}
local function append(target, values)
    for _, value in ipairs(values) do
        target[#target + 1] = value
    end
end
local function read_file(path)
    local file = assert(io.open(path, "rb"))
    local contents = file:read("a")
    file:close()
    return contents
end
local function ratio(compressed, original)
    return original > 0 and tostring(1000 * compressed // original) or "-"
end
local function method_name(number)
    return methods[number + 1] or "#" .. number
end
local function integers(values)
    local fields = {}
    for index, value in ipairs(values) do
        fields[index] = tostring(value)
    end
    return table.concat(fields, " ")
end
local function adler(data)
    local first, second = 1, 0
    for index = 1, #data do
        first = (first + data:byte(index)) % 65521
        second = (second + first) % 65521
    end
    return second * 65536 + first
end
local function modular_power(base, exponent)
    local result = 1
    while exponent > 0 do
        if exponent % 2 == 1 then
            result = result * base % 65521
        end
        base, exponent = base * base % 65521, exponent // 2
    end
    return result
end
local function repair_byte(data, stored, computed)
    local da = (stored % 65536 - computed % 65536) % 65521
    local db = (stored // 65536 - computed // 65536) % 65521
    local delta
    if da >= 1 and da <= 255 then
        delta = da
    elseif da >= 65266 and da <= 65520 then
        delta = da - 65521
    else
        return nil
    end
    local inverse = modular_power(delta % 65521, 65519)
    local distance = db * inverse % 65521
    if distance < 1 or distance > #data then
        return nil
    end
    local position = #data - distance
    local before = data:byte(position + 1)
    local after = before + delta
    if after < 0 or after > 255 then
        return nil
    end
    local repaired = data:sub(1, position) .. string.char(after) .. data:sub(position + 2)
    if adler(repaired) ~= stored then
        return nil
    end
    return repaired, {position = position, before = before, after = after}
end
local function fixed_lengths(count)
    local width, result = bitio.bits(count - 1), {}
    local shorter = (1 << width) - count
    for symbol = 0, count - 1 do
        result[symbol + 1] = symbol < shorter and width - 1 or width
    end
    return result
end
local function write_table(writer, lengths)
    local symbol = 1
    while symbol <= #lengths do
        if lengths[symbol] > 0 then
            writer:write(lengths[symbol], 4)
            symbol = symbol + 1
        else
            local run = 1
            while run < 256 and symbol + run <= #lengths and lengths[symbol + run] == 0 do
                run = run + 1
            end
            writer:write(0, 4)
            writer:write(run - 1, 8)
            symbol = symbol + run
        end
    end
end
local function read_table(reader, count)
    local lengths = {}
    while #lengths < count do
        local length = reader:read(4, 0)
        if length > 0 then
            lengths[#lengths + 1] = length
        else
            local run = reader:read(8, 0) + 1
            if #lengths + run > count then
                bitio.fail("bad_table", 0)
            end
            for index = 1, run do
                lengths[#lengths + 1] = 0
            end
        end
    end
    local used, only, kraft = 0, 0, 0
    for _, length in ipairs(lengths) do
        if length > 0 then
            used, only, kraft = used + 1, length, kraft + (1 << (15 - length))
        end
    end
    if (used == 1 and only ~= 1) or (used >= 2 and kraft ~= 32768) then
        bitio.fail("bad_table", 0)
    end
    return lengths
end
local function symbol_reader(lengths)
    local codes, lookup, maximum = huffman.canonical(lengths), {}, 0
    for index, length in ipairs(lengths) do
        if length > 0 then
            lookup[length] = lookup[length] or {}
            lookup[length][codes[index]] = index - 1
            maximum = math.max(maximum, length)
        end
    end
    return function(reader, position)
        if maximum == 0 then
            bitio.fail("bad_code", position)
        end
        local code = 0
        for width = 1, maximum do
            code = code * 2 + reader:read(1, position)
            local symbol = lookup[width] and lookup[width][code]
            if symbol ~= nil then
                return symbol
            end
        end
        bitio.fail("bad_code", position)
    end
end
local function encode_lz(tokens, offset_bits, length_bits)
    local writer = bitio.writer()
    for _, token in ipairs(tokens) do
        if token.literal ~= nil then
            writer:write(0, 1)
            writer:write(token.literal, 8)
        else
            writer:write(1, 1)
            writer:write(token.distance - 1, offset_bits)
            writer:write(token.length - 3, length_bits)
        end
    end
    return writer:finish()
end
local function decode_lz(payload, original, offset_bits, length_bits)
    local reader, output = bitio.reader(payload), {}
    while #output < original do
        if reader:read(1, #output) == 0 then
            output[#output + 1] = reader:read(8, #output)
        else
            local distance = reader:read(offset_bits, #output) + 1
            local length = reader:read(length_bits, #output) + 3
            lz77.copy_match(output, distance, length, original)
        end
    end
    return bitio.bytes(output)
end
local function write_tokens(writer, tokens, literal_lengths, distance_lengths)
    local literal_codes, distance_codes = huffman.canonical(literal_lengths), huffman.canonical(distance_lengths)
    for _, token in ipairs(tokens) do
        if token.literal ~= nil then
            writer:write(literal_codes[token.literal + 1], literal_lengths[token.literal + 1])
        else
            local symbol = 256 + token.length - 3
            writer:write(literal_codes[symbol + 1], literal_lengths[symbol + 1])
            local offset = token.distance - 1
            local slot = bitio.bits(offset)
            writer:write(distance_codes[slot + 1], distance_lengths[slot + 1])
            if slot >= 2 then
                writer:write(offset - (1 << (slot - 1)), slot - 1)
            end
        end
    end
end
local function encode_lzh(tokens, params)
    local literal_frequencies, distance_frequencies = {}, {}
    local literal_count, distance_count = 256 + (1 << params.K), params.B + 1
    for index = 1, literal_count do
        literal_frequencies[index] = 0
    end
    for index = 1, distance_count do
        distance_frequencies[index] = 0
    end
    for _, token in ipairs(tokens) do
        local symbol = token.literal ~= nil and token.literal or 256 + token.length - 3
        literal_frequencies[symbol + 1] = literal_frequencies[symbol + 1] + 1
        if token.distance then
            local slot = bitio.bits(token.distance - 1)
            distance_frequencies[slot + 1] = distance_frequencies[slot + 1] + 1
        end
    end
    local literal_lengths, literal_halvings = huffman.limited_lengths(literal_frequencies, params.M)
    local distance_lengths, distance_halvings = huffman.limited_lengths(distance_frequencies, params.M)
    local fixed = bitio.writer()
    fixed:write(0, 1)
    write_tokens(fixed, tokens, fixed_lengths(literal_count), fixed_lengths(distance_count))
    local fixed_bits = fixed.bit_count - 1
    local dynamic = bitio.writer()
    dynamic:write(1, 1)
    write_table(dynamic, literal_lengths)
    write_table(dynamic, distance_lengths)
    local table_bits = dynamic.bit_count - 1
    write_tokens(dynamic, tokens, literal_lengths, distance_lengths)
    local code_bits = dynamic.bit_count - 1 - table_bits
    local use_fixed = fixed_bits <= table_bits + code_bits
    local stats = {mode = use_fixed and "fixed" or "dynamic", fixed_bits = fixed_bits, table_bits = table_bits, code_bits = code_bits,
        halvings = literal_halvings + distance_halvings, litlen_used = 0, litlen_max = 0, offset_used = 0, offset_max = 0, slots = distance_frequencies}
    for _, length in ipairs(literal_lengths) do
        if length > 0 then
            stats.litlen_used = stats.litlen_used + 1
        end
        stats.litlen_max = math.max(stats.litlen_max, length)
    end
    for _, length in ipairs(distance_lengths) do
        if length > 0 then
            stats.offset_used = stats.offset_used + 1
        end
        stats.offset_max = math.max(stats.offset_max, length)
    end
    return (use_fixed and fixed or dynamic):finish(), stats
end
local function decode_lzh(payload, original, offset_bits, length_bits)
    local reader = bitio.reader(payload)
    local literal_count, distance_count = 256 + (1 << length_bits), offset_bits + 1
    local literal_lengths, distance_lengths
    if reader:read(1, 0) == 1 then
        literal_lengths = read_table(reader, literal_count)
        distance_lengths = read_table(reader, distance_count)
    else
        literal_lengths, distance_lengths = fixed_lengths(literal_count), fixed_lengths(distance_count)
    end
    local read_literal, read_distance = symbol_reader(literal_lengths), symbol_reader(distance_lengths)
    local output = {}
    while #output < original do
        local symbol = read_literal(reader, #output)
        if symbol < 256 then
            output[#output + 1] = symbol
        else
            local length = symbol - 253
            local slot = read_distance(reader, #output)
            local offset = slot
            if slot >= 2 then
                offset = (1 << (slot - 1)) + reader:read(slot - 1, #output)
            end
            lz77.copy_match(output, offset + 1, length, original)
        end
    end
    return bitio.bytes(output)
end
local function decode(method, payload, original, offset_bits, length_bits)
    if method == 0 then
        if #payload < original then
            bitio.fail("end_of_data", #payload)
        end
        return payload:sub(1, original)
    elseif method == 1 then
        return lzw.decode(payload, original)
    elseif method == 2 then
        return decode_lz(payload, original, offset_bits, length_bits)
    elseif method == 3 then
        return decode_lzh(payload, original, offset_bits, length_bits)
    else
        return arith.decode(payload, original)
    end
end
local function encode_file(name, data, params)
    local tokens = lz77.tokenize(data, params.B, params.K)
    local zw_payload, zw_stats = lzw.encode(data)
    local lz_payload = encode_lz(tokens, params.B, params.K)
    local zh_payload, zh_stats = encode_lzh(tokens, params)
    local arith_payload, arith_stats = arith.encode(data)
    local payloads = {data, zw_payload, lz_payload, zh_payload, arith_payload}
    local best = 1
    for method = 2, 5 do
        if #payloads[method] < #payloads[best] then
            best = method
        end
    end
    local stats = {tokens = #tokens, literals = 0, matches = 0, matched = 0, longest = 0, farthest = 0}
    for _, token in ipairs(tokens) do
        if token.literal ~= nil then
            stats.literals = stats.literals + 1
        else
            stats.matches, stats.matched = stats.matches + 1, stats.matched + token.length
            stats.longest, stats.farthest = math.max(stats.longest, token.length), math.max(stats.farthest, token.distance)
        end
    end
    return {name = name, data = data, payloads = payloads, best = best - 1, payload = payloads[best], lzw = zw_stats, lz = stats, lzh = zh_stats, arith = arith_stats}
end
local function uint_bytes(value, count)
    local values = {}
    for index = count, 1, -1 do
        values[index], value = value % 256, value // 256
    end
    return bitio.bytes(values)
end
local function read_uint(data, position, count)
    local value = 0
    for index = 1, count do
        value = value * 256 + data:byte(position + index)
    end
    return value
end
local function build_archive(encodings, params)
    local parts = {"TXAR", string.char(params.B, params.K), uint_bytes(#encodings, 2)}
    for _, encoding in ipairs(encodings) do
        local header = string.char(#encoding.name) .. encoding.name .. string.char(encoding.best)
            .. uint_bytes(#encoding.data, 4) .. uint_bytes(#encoding.payload, 4) .. uint_bytes(adler(encoding.data), 4)
        local check = 0
        for index = 1, #header do
            check = (check + header:byte(index)) % 256
        end
        parts[#parts + 1] = header .. string.char(check) .. encoding.payload
    end
    return table.concat(parts)
end
local function parse_archive(archive)
    local parsed = {size = #archive, entries = {}, intact = {}, stopped = false, trailing = 0, declared = 0}
    if #archive < 8 or archive:sub(1, 4) ~= "TXAR" then
        parsed.error = "bad_magic"
        return parsed
    end
    parsed.B, parsed.K = archive:byte(5, 6)
    if parsed.B < 6 or parsed.B > 12 or parsed.K < 2 or parsed.K > 5 then
        parsed.error = "bad_params"
        return parsed
    end
    parsed.declared = read_uint(archive, 6, 2)
    local position = 8
    for number = 1, parsed.declared do
        local entry = {number = number, offset = position, valid_header = false}
        parsed.entries[#parsed.entries + 1] = entry
        if position >= #archive or position + 15 + archive:byte(position + 1) > #archive then
            entry.status, parsed.stopped = "truncated", true
            break
        end
        local length = archive:byte(position + 1)
        local name = archive:sub(position + 2, position + 1 + length)
        local cursor = position + 1 + length
        local start = position + 15 + length
        entry.name, entry.method = name, archive:byte(cursor + 1)
        entry.original, entry.compressed, entry.checksum = read_uint(archive, cursor + 1, 4), read_uint(archive, cursor + 5, 4), read_uint(archive, cursor + 9, 4)
        entry.start, entry.finish = start, start + entry.compressed
        local check = 0
        for index = position + 1, start - 1 do
            check = (check + archive:byte(index)) % 256
        end
        entry.valid_header = length >= 1 and length <= 32 and name:match("^[a-z0-9._%-]+$") ~= nil and check == archive:byte(start)
        if not entry.valid_header then
            entry.status, position = "bad_header", entry.finish
            if position > #archive then
                parsed.stopped = true
                break
            end
        elseif entry.finish > #archive then
            entry.status, parsed.stopped = "truncated", true
            break
        else
            if entry.method >= 5 then
                entry.status = "unsupported"
            else
                local success, result = pcall(decode, entry.method, archive:sub(start + 1, entry.finish), entry.original, parsed.B, parsed.K)
                if not success then
                    if type(result) ~= "table" or not result.decode_error then
                        error(result, 0)
                    end
                    entry.status, entry.error = "error", result
                else
                    entry.data, entry.computed = result, adler(result)
                    if entry.computed == entry.checksum then
                        entry.status = "ok"
                    else
                        local repaired, record = repair_byte(result, entry.checksum, entry.computed)
                        if repaired then
                            entry.status, entry.data, entry.repair = "repaired", repaired, record
                        else
                            entry.status = "checksum"
                        end
                    end
                end
            end
            if entry.status == "ok" or entry.status == "repaired" then
                parsed.intact[#parsed.intact + 1] = entry
            end
            position = entry.finish
        end
    end
    if not parsed.stopped then
        parsed.trailing = #archive - position
    end
    return parsed
end
local function verify(archive, encodings)
    local parsed, verified = parse_archive(archive), 0
    for index, entry in ipairs(parsed.entries) do
        if encodings[index] and entry.status == "ok" and entry.data == encodings[index].data then
            verified = verified + 1
        end
    end
    return #parsed.entries, verified
end
local function sizes_report(encodings, params, archive, examined, verified)
    local lines = {"params offset_bits " .. params.B .. " length_bits " .. params.K .. " window " .. (1 << params.B) .. " lookahead " .. ((1 << params.K) + 2) .. " max_code_length " .. params.M}
    local totals, chosen, original_total, best_total = {0, 0, 0, 0, 0}, {0, 0, 0, 0, 0}, 0, 0
    for _, encoding in ipairs(encodings) do
        local original = #encoding.data
        original_total, best_total = original_total + original, best_total + #encoding.payload
        chosen[encoding.best + 1] = chosen[encoding.best + 1] + 1
        local fields = {"file " .. encoding.name .. " original " .. original}
        for index, method in ipairs(methods) do
            local compressed = #encoding.payloads[index]
            totals[index] = totals[index] + compressed
            fields[#fields + 1] = method .. " " .. compressed .. " " .. ratio(compressed, original)
        end
        fields[#fields + 1] = "best " .. method_name(encoding.best)
        lines[#lines + 1] = table.concat(fields, " ")
    end
    local total_fields, chosen_fields = {"total original " .. original_total}, {"chosen"}
    for index, method in ipairs(methods) do
        total_fields[#total_fields + 1] = method .. " " .. totals[index] .. " " .. ratio(totals[index], original_total)
        chosen_fields[#chosen_fields + 1] = method .. " " .. chosen[index]
    end
    total_fields[#total_fields + 1] = "best " .. best_total .. " " .. ratio(best_total, original_total)
    append(lines, {table.concat(total_fields, " "), table.concat(chosen_fields, " "),
        "archive bytes " .. #archive .. " entries " .. #encodings .. " ratio " .. ratio(#archive, original_total), "verify entries " .. examined .. " ok " .. verified})
    return lines
end
local function analysis_report(encodings)
    local lines = {}
    for _, encoding in ipairs(encodings) do
        local name, zw, z, zh, arithmetic = encoding.name, encoding.lzw, encoding.lz, encoding.lzh, encoding.arith
        append(lines, {"lzw " .. name .. " codes " .. zw.codes .. " clears " .. zw.clears .. " widths " .. integers(zw.widths) .. " longest " .. zw.longest,
            "lz77 " .. name .. " tokens " .. z.tokens .. " literals " .. z.literals .. " matches " .. z.matches .. " matched " .. z.matched .. " longest " .. z.longest .. " farthest " .. z.farthest,
            "lzh " .. name .. " mode " .. zh.mode .. " fixed_bits " .. zh.fixed_bits .. " table_bits " .. zh.table_bits .. " code_bits " .. zh.code_bits .. " halvings " .. zh.halvings .. " litlen_used " .. zh.litlen_used .. " litlen_max " .. zh.litlen_max .. " offset_used " .. zh.offset_used .. " offset_max " .. zh.offset_max,
            "slots " .. name .. " " .. integers(zh.slots), "arith " .. name .. " bits " .. arithmetic.bits .. " contexts " .. arithmetic.contexts .. " rescales " .. arithmetic.rescales})
    end
    return lines
end
local function listing_report(parsed)
    if parsed.error then
        return {"archive bytes " .. parsed.size .. " error " .. parsed.error}
    end
    local lines = {"archive bytes " .. parsed.size .. " offset_bits " .. parsed.B .. " length_bits " .. parsed.K .. " entries " .. parsed.declared}
    local totals, listed = {}, 0
    for index = 1, 5 do
        totals[index] = {0, 0, 0}
    end
    for _, entry in ipairs(parsed.entries) do
        local prefix = "entry " .. entry.number .. " offset " .. entry.offset
        if not entry.valid_header then
            lines[#lines + 1] = prefix .. (entry.status == "bad_header" and " bad_header" or " truncated header")
        else
            listed = listed + 1
            lines[#lines + 1] = prefix .. " method " .. method_name(entry.method) .. " original " .. entry.original .. " compressed " .. entry.compressed .. " ratio " .. ratio(entry.compressed, entry.original)
                .. " adler " .. string.format("%08x", entry.checksum) .. " name " .. entry.name
            if entry.method < 5 then
                local total = totals[entry.method + 1]
                total[1], total[2], total[3] = total[1] + 1, total[2] + entry.original, total[3] + entry.compressed
            end
        end
    end
    for index, method in ipairs(methods) do
        local total = totals[index]
        lines[#lines + 1] = "method " .. method .. " entries " .. total[1] .. " original " .. total[2] .. " compressed " .. total[3] .. " ratio " .. ratio(total[3], total[2])
    end
    lines[#lines + 1] = "end listed " .. listed .. " of " .. parsed.declared .. " stop " .. (parsed.stopped and "truncated" or "complete") .. " trailing " .. parsed.trailing
    return lines
end
local function entry_test_line(entry, archive_size)
    local prefix = "entry " .. entry.number .. " offset " .. entry.offset
    if not entry.valid_header then
        return prefix .. " status " .. (entry.status == "bad_header" and "bad_header" or "truncated header")
    end
    local line = prefix .. " name " .. entry.name .. " method " .. method_name(entry.method) .. " status " .. entry.status
    if entry.status == "repaired" then
        line = line .. " byte " .. entry.repair.position .. " from " .. entry.repair.before .. " to " .. entry.repair.after
    elseif entry.status == "checksum" then
        line = line .. " stored " .. string.format("%08x", entry.checksum) .. " computed " .. string.format("%08x", entry.computed)
    elseif entry.status == "error" then
        line = line .. " " .. entry.error.kind .. " at " .. entry.error.position
    elseif entry.status == "truncated" then
        line = line .. " payload have " .. (archive_size - entry.start) .. " need " .. entry.compressed
    end
    return line
end
local function test_report(parsed, encodings, salvaged, verified)
    local lines = {}
    if parsed.error then
        lines[1] = "archive error " .. parsed.error
    else
        local counts = {}
        for _, status in ipairs(statuses) do
            counts[status] = 0
        end
        for _, entry in ipairs(parsed.entries) do
            lines[#lines + 1] = entry_test_line(entry, parsed.size)
            counts[entry.status] = counts[entry.status] + 1
        end
        local fields = {"summary entries " .. parsed.declared .. " checked " .. #parsed.entries}
        for _, status in ipairs(statuses) do
            fields[#fields + 1] = status .. " " .. counts[status]
        end
        fields[#fields + 1] = "missing " .. (parsed.declared - #parsed.entries) .. " trailing " .. parsed.trailing
        lines[#lines + 1] = table.concat(fields, " ")
    end
    local original = 0
    for index, encoding in ipairs(encodings) do
        local entry = parsed.intact[index]
        original = original + #encoding.data
        lines[#lines + 1] = "salvage " .. entry.name .. " method " .. method_name(encoding.best) .. " compressed " .. #encoding.payload .. " was " .. method_name(entry.method) .. " " .. entry.compressed
    end
    lines[#lines + 1] = "salvaged entries " .. #encodings .. " bytes " .. #salvaged .. " original " .. original .. " verified " .. verified
    return lines
end
local function text_lines(data)
    local lines = {}
    for line in data:gmatch("(.-)\n") do
        lines[#lines + 1] = line
    end
    return lines
end
local function extraction_report(entries)
    local lines = {}
    for _, entry in ipairs(entries) do
        local contents, words, longest = text_lines(entry.data), 0, 0
        for _, line in ipairs(contents) do
            longest = math.max(longest, #line)
            for word in line:gmatch("[^ ]+") do
                words = words + 1
            end
        end
        lines[#lines + 1] = "file " .. entry.name .. " bytes " .. #entry.data .. " lines " .. #contents .. " words " .. words .. " longest " .. longest
        append(lines, contents)
    end
    return lines
end
local function edit_list(old, new)
    local a, b, below, current, decisions = #old, #new, {}, {}, {}
    for column = 1, b + 1 do
        below[column], current[column] = 0, 0
    end
    for i = a - 1, 0, -1 do
        local deleted, right = {}, 0
        for index = 1, (b + 7) // 8 do
            deleted[index] = 0
        end
        for j = b - 1, 0, -1 do
            local length
            if old[i + 1] == new[j + 1] then
                length = below[j + 2] + 1
            elseif below[j + 1] >= right then
                length = below[j + 1]
                local byte = j // 8 + 1
                deleted[byte] = deleted[byte] | (1 << (j % 8))
            else
                length = right
            end
            current[j + 1], right = length, length
        end
        decisions[i + 1] = bitio.bytes(deleted)
        below, current = current, below
    end
    local i, j, edits, removed, added = 0, 0, {}, 0, 0
    while i < a or j < b do
        if i < a and j < b and old[i + 1] == new[j + 1] then
            i, j = i + 1, j + 1
        elseif j == b or (i < a and (decisions[i + 1]:byte(j // 8 + 1) & (1 << (j % 8))) ~= 0) then
            edits[#edits + 1] = "-" .. (i + 1) .. ":" .. old[i + 1]
            i, removed = i + 1, removed + 1
        else
            edits[#edits + 1] = "+" .. (j + 1) .. ":" .. new[j + 1]
            j, added = j + 1, added + 1
        end
    end
    return edits, removed, added
end
local function comparison_report(entries, files)
    local originals, seen, lines = {}, {}, {}
    for _, file in ipairs(files) do
        originals[file.name] = file.data
    end
    for _, entry in ipairs(entries) do
        seen[entry.name] = true
        local original = originals[entry.name]
        if original == nil then
            lines[#lines + 1] = "archive_only " .. entry.name
        else
            local old, new = text_lines(entry.data), text_lines(original)
            if entry.data == original then
                lines[#lines + 1] = "same " .. entry.name .. " lines " .. #old
            else
                local first = 0
                while first < math.min(#old, #new) and old[first + 1] == new[first + 1] do
                    first = first + 1
                end
                local edits, removed, added = edit_list(old, new)
                lines[#lines + 1] = "differs " .. entry.name .. " first_line " .. (first + 1) .. " archive_lines " .. #old .. " manifest_lines " .. #new .. " removed " .. removed .. " added " .. added
                append(lines, edits)
            end
        end
    end
    for _, file in ipairs(files) do
        if not seen[file.name] then
            lines[#lines + 1] = "new " .. file.name
        end
    end
    return lines
end
local function save(name, lines)
    local file = assert(io.open("output/" .. name, "w"))
    for _, line in ipairs(lines) do
        file:write(line, "\n")
    end
    file:close()
end
local function hex_lines(data)
    local lines = {}
    for start = 1, #data, 32 do
        local fields = {}
        for index = start, math.min(start + 31, #data) do
            fields[#fields + 1] = string.format("%02x", data:byte(index))
        end
        lines[#lines + 1] = table.concat(fields)
    end
    return lines
end
local manifest = {}
for line in io.lines("input/manifest.txt") do
    manifest[#manifest + 1] = line
end
local params = {B = tonumber(manifest[1]:match(" (%d+)$")), K = tonumber(manifest[2]:match(" (%d+)$")), M = tonumber(manifest[3]:match(" (%d+)$"))}
local files, encodings = {}, {}
for index = 4, #manifest do
    local name = manifest[index]:sub(6)
    local data = read_file("input/files/" .. name)
    files[#files + 1] = {name = name, data = data}
    encodings[#encodings + 1] = encode_file(name, data, params)
end
local created = build_archive(encodings, params)
local examined, verified = verify(created, encodings)
local hexadecimal = read_file("input/archive.hex"):gsub("\n", "")
local archive_parts = {}
for position = 1, #hexadecimal, 2 do
    archive_parts[#archive_parts + 1] = string.char(tonumber(hexadecimal:sub(position, position + 1), 16))
end
local parsed = parse_archive(table.concat(archive_parts))
local salvage_params = parsed.error and params or {B = parsed.B, K = parsed.K, M = params.M}
local salvage_encodings = {}
for _, entry in ipairs(parsed.intact) do
    salvage_encodings[#salvage_encodings + 1] = encode_file(entry.name, entry.data, salvage_params)
end
local salvaged = build_archive(salvage_encodings, salvage_params)
local _, salvage_verified = verify(salvaged, salvage_encodings)
os.execute('mkdir -p output')
save("sizes.txt", sizes_report(encodings, params, created, examined, verified))
save("analysis.txt", analysis_report(encodings))
save("archive.hex", hex_lines(created))
save("listing.txt", listing_report(parsed))
save("test_report.txt", test_report(parsed, salvage_encodings, salvaged, salvage_verified))
save("extracted.txt", extraction_report(parsed.intact))
save("compare.txt", comparison_report(parsed.intact, files))
save("salvaged.hex", hex_lines(salvaged))
