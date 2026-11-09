local schema = require('schema_io')
local bits = require('bitstream')
local encoding = require('encoding')
local QueryParser = require('query')
local NULL, UNKNOWN = schema.NULL, schema.UNKNOWN
local append, Reader = bits.append, bits.Reader
local scan_names = {'row_groups_read', 'row_groups_skipped', 'pages_read', 'pages_skipped', 'pages_unneeded',
    'dictionary_pages_read', 'bytes_read', 'rows_scanned', 'rows_matched'}
local function slice(values, first, last) local result = {}; for index = first, last do result[#result + 1] = values[index] end; return result end
local function keys(values) local result = {}; for key in pairs(values) do result[#result + 1] = key end; table.sort(result); return result end
local function counter() return setmetatable({}, {__index = function() return 0 end}) end
local function statistics(kind, values)
    local low, high
    for _, value in ipairs(values) do
        if value ~= NULL then
            if low == nil or schema.less(kind, value, low) then low = value end
            if high == nil or schema.less(kind, high, value) then high = value end
        end
    end
    if low ~= nil then return {low, high} end
end
local function statistics_text(column, bounds)
    if not bounds then return 'stats none' end
    return 'min ' .. schema.value_text(column.kind, bounds[1]) .. ' max ' .. schema.value_text(column.kind, bounds[2])
end
local function method_list(methods)
    local names = {}; for _, method in ipairs(methods) do names[#names + 1] = encoding.methods[method] end; return table.concat(names, ',')
end
local function column_line(index, column) return 'column ' .. index .. ' ' .. column.name .. ' ' .. column.kind .. ' ' .. (column.nullable and 'NULLABLE' or 'REQUIRED') end
local function hex(data) local parts = {}; for index, byte in ipairs(data) do parts[index] = string.format('%02x', byte) end; return table.concat(parts) end
local function checksum_text(value) return string.format('%08x', value) end
local function build_page(column, dictionary_page, method, values, dictionary)
    local body, nulls, bounds = {}, 0, nil
    if dictionary_page then body = encoding.encode_values(column.kind, 0, values)
    else
        local present, definitions = {}, {}
        for _, value in ipairs(values) do
            definitions[#definitions + 1] = value ~= NULL and 1 or 0
            if value ~= NULL then present[#present + 1] = value else nulls = nulls + 1 end
        end
        bounds = statistics(column.kind, values)
        if column.nullable then local data = bits.hybrid_encode(definitions, 1); append(body, bits.integer(#data)); append(body, data) end
        append(body, encoding.encode_values(column.kind, method, present, dictionary))
    end
    local header = {dictionary_page and 1 or 0, method}
    append(header, bits.uleb(#values)); append(header, bits.uleb(nulls)); append(header, bits.uleb(#body))
    append(header, bits.integer(bits.adler32(body))); append(header, encoding.encode_statistics(column.kind, bounds)); append(header, body)
    return header
end
local function build_chunk(column, values, method, page_size, dictionary_limit)
    local pages = {}; for first = 1, #values, page_size do pages[#pages + 1] = slice(values, first, math.min(first + page_size - 1, #values)) end
    local dictionary, dictionary_pages = {}, 0
    if method == 1 then
        local known, dictionary_bytes = {}, 0
        for _, page in ipairs(pages) do
            local proposed, additions = {}, {}; for value in pairs(known) do proposed[value] = true end
            for _, value in ipairs(page) do if value ~= NULL and not proposed[value] then proposed[value] = true; additions[#additions + 1] = value end end
            local size = dictionary_bytes + #encoding.encode_values(column.kind, 0, additions)
            if size > dictionary_limit then break end
            append(dictionary, additions); known, dictionary_bytes, dictionary_pages = proposed, size, dictionary_pages + 1
        end
        if #dictionary == 0 then dictionary_pages = 0 end
    end
    local data, methods, nulls = {}, {}, 0
    if dictionary_pages > 0 then append(data, build_page(column, true, 0, dictionary)) end
    for number, page in ipairs(pages) do
        local selected = method
        if method == 1 then selected = number <= dictionary_pages and 1 or 0 end
        methods[selected] = true; append(data, build_page(column, false, selected, page, dictionary))
    end
    for _, value in ipairs(values) do if value == NULL then nulls = nulls + 1 end end
    return {data = data, methods = keys(methods), has_dictionary = dictionary_pages > 0, page_count = #pages, nulls = nulls,
        bounds = statistics(column.kind, values), fallback = method == 1 and #pages - dictionary_pages or 0}
end
local function build_file(columns, rows, options)
    local data, groups, report = bits.bytes('MPTC'), {}, {'row_group,column,encoding,bytes,fallback_pages,chosen'}
    local method_numbers, type_numbers = {}, {}
    for method = 0, 4 do method_numbers[encoding.methods[method]] = method end
    for index, kind in ipairs(schema.types) do type_numbers[kind] = index - 1 end
    for first = 1, #rows, options.row_group_size do
        local last, chunks = math.min(first + options.row_group_size - 1, #rows), {}
        for index, column in ipairs(columns) do
            local values, choices = {}, {}
            for row = first, last do values[#values + 1] = rows[row][index] end
            for _, method in ipairs(encoding.candidates[column.kind]) do choices[method] = build_chunk(column, values, method, options.page_size, options.dictionary_limit) end
            local requested, chosen = options.encoding[column.name], nil
            if requested == 'AUTO' then
                for _, method in ipairs(encoding.candidates[column.kind]) do if chosen == nil or #choices[method].data < #choices[chosen].data then chosen = method end end
            else chosen = method_numbers[requested]; if chosen == 1 and not choices[chosen].has_dictionary then chosen = 0 end end
            for _, method in ipairs(encoding.candidates[column.kind]) do
                local choice = choices[method]
                report[#report + 1] = #groups .. ',' .. column.name .. ',' .. encoding.methods[method] .. ',' .. #choice.data .. ',' .. choice.fallback .. ',' .. (method == chosen and 'yes' or 'no')
            end
            local chunk = choices[chosen]; chunk.offset = #data; append(data, chunk.data); chunks[#chunks + 1] = chunk
        end
        groups[#groups + 1] = {rows = last - first + 1, chunks = chunks}
    end
    local footer = {}; append(footer, bits.uleb(1)); append(footer, bits.uleb(#columns))
    for _, column in ipairs(columns) do append(footer, bits.uleb(#column.name)); append(footer, bits.bytes(column.name)); append(footer, {type_numbers[column.kind], column.nullable and 1 or 0}) end
    append(footer, bits.uleb(#rows)); append(footer, bits.uleb(#groups))
    for _, group in ipairs(groups) do
        append(footer, bits.uleb(group.rows))
        for index, chunk in ipairs(group.chunks) do
            append(footer, bits.uleb(chunk.offset)); append(footer, bits.uleb(#chunk.data)); append(footer, bits.uleb(#chunk.methods)); append(footer, chunk.methods)
            footer[#footer + 1] = chunk.has_dictionary and 1 or 0
            append(footer, bits.uleb(chunk.page_count)); append(footer, bits.uleb(chunk.nulls)); append(footer, encoding.encode_statistics(columns[index].kind, chunk.bounds))
        end
    end
    append(data, footer); append(data, bits.integer(#footer)); append(data, bits.bytes('MPTC'))
    return data, report
end
local function parse_file(data)
    local footer_size = Reader.new(data, #data - 8):integer()
    local footer_offset = #data - 8 - footer_size
    local reader = Reader.new(data, footer_offset)
    local version, columns = reader:uleb(), {}
    local column_count = reader:uleb()
    for index = 1, column_count do
        local name_size = reader:uleb(); local name = bits.text(reader:read(name_size)); local kind = schema.types[reader:byte() + 1]
        columns[index] = {name = name, kind = kind, nullable = reader:byte() ~= 0}
    end
    local row_count = reader:uleb()
    local group_count = reader:uleb()
    local groups, first_row = {}, 0
    for number = 1, group_count do
        local count, chunks = reader:uleb(), {}
        for index, column in ipairs(columns) do
            local offset = reader:uleb(); local size = reader:uleb(); local methods = {}
            local method_count = reader:uleb(); for method = 1, method_count do methods[method] = reader:byte() end
            local has_dictionary = reader:byte() ~= 0; local pages = reader:uleb(); local nulls = reader:uleb()
            chunks[index] = {offset = offset, size = size, methods = methods, has_dictionary = has_dictionary, page_count = pages, nulls = nulls,
                bounds = encoding.decode_statistics(reader, column.kind)}
        end
        groups[number] = {rows = count, first_row = first_row, chunks = chunks}; first_row = first_row + count
    end
    for _, group in ipairs(groups) do
        for index, chunk in ipairs(group.chunks) do
            local page_reader, pages = Reader.new(data, chunk.offset), {}
            while page_reader.position < chunk.offset + chunk.size do
                local offset = page_reader.position; local kind = page_reader:byte(); local method = page_reader:byte()
                local count = page_reader:uleb(); local nulls = page_reader:uleb(); local body_size = page_reader:uleb(); local checksum = page_reader:integer()
                local bounds = encoding.decode_statistics(page_reader, columns[index].kind)
                local body_offset = page_reader.position
                pages[#pages + 1] = {offset = offset, kind = kind, method = method, count = count, nulls = nulls, body_size = body_size,
                    checksum = checksum, bounds = bounds, body_offset = body_offset, header_size = body_offset - offset, size = body_offset - offset + body_size}
                page_reader.position = page_reader.position + body_size
            end
            if chunk.has_dictionary then chunk.dictionary = table.remove(pages, 1) end
            chunk.pages = pages
        end
    end
    return {data = data, version = version, columns = columns, rows = row_count, groups = groups, footer_size = footer_size, footer_offset = footer_offset}
end
local function page_body(file, page) return slice(file.data, page.body_offset + 1, page.body_offset + page.body_size) end
local function decode_dictionary(file, column, page) return encoding.decode_values(Reader.new(page_body(file, page)), column.kind, 0, page.count) end
local function decode_page(file, column, page, dictionary)
    local reader, definitions = Reader.new(page_body(file, page)), {}
    if column.nullable then local size = reader:integer(); definitions = bits.hybrid_decode(Reader.new(reader:read(size)), 1, page.count)
    else for index = 1, page.count do definitions[index] = 1 end end
    local present = 0; for _, definition in ipairs(definitions) do if definition == 1 then present = present + 1 end end
    local values = encoding.decode_values(reader, column.kind, page.method, present, dictionary)
    local rows, index = {}, 1
    for row, definition in ipairs(definitions) do
        if definition == 1 then rows[row] = values[index]; index = index + 1 else rows[row] = NULL end
    end
    return rows
end

local function verify_and_describe(file, original)
    local columns = file.columns
    local lines = {'file bytes ' .. #file.data .. ' footer_offset ' .. file.footer_offset .. ' footer_bytes ' .. file.footer_size,
        'table version ' .. file.version .. ' rows ' .. file.rows .. ' columns ' .. #columns .. ' row_groups ' .. #file.groups}
    local summaries = {}
    for index, column in ipairs(columns) do lines[#lines + 1] = column_line(index - 1, column); summaries[index] = {bytes = 0, data_pages = 0, dictionary_pages = 0, methods = {}} end
    local cells, nulls, mismatches, checksum_errors = 0, 0, 0, 0
    for number, group in ipairs(file.groups) do
        local size = 0; for _, chunk in ipairs(group.chunks) do size = size + chunk.size end
        lines[#lines + 1] = 'row_group ' .. (number - 1) .. ' rows ' .. group.rows .. ' first_row ' .. group.first_row .. ' bytes ' .. size
        for index, column in ipairs(columns) do
            local chunk, summary = group.chunks[index], summaries[index]
            lines[#lines + 1] = 'chunk ' .. (number - 1) .. ' ' .. column.name .. ' offset ' .. chunk.offset .. ' size ' .. chunk.size .. ' encodings ' .. method_list(chunk.methods)
                .. ' dictionary ' .. (chunk.has_dictionary and 'yes' or 'no') .. ' pages ' .. chunk.page_count .. ' nulls ' .. chunk.nulls .. ' ' .. statistics_text(column, chunk.bounds)
            summary.bytes, summary.data_pages, summary.dictionary_pages = summary.bytes + chunk.size, summary.data_pages + chunk.page_count, summary.dictionary_pages + (chunk.has_dictionary and 1 or 0)
            for _, method in ipairs(chunk.methods) do summary.methods[method] = true end
            local dictionary
            if chunk.dictionary then
                local page = chunk.dictionary
                if bits.adler32(page_body(file, page)) ~= page.checksum then checksum_errors = checksum_errors + 1 end
                dictionary = decode_dictionary(file, column, page)
                lines[#lines + 1] = 'page ' .. (number - 1) .. ' ' .. column.name .. ' dict offset ' .. page.offset .. ' header ' .. page.header_size .. ' body ' .. page.body_size .. ' checksum ' .. checksum_text(page.checksum) .. ' entries ' .. page.count
            end
            local row = group.first_row + 1
            for page_number, page in ipairs(chunk.pages) do
                if bits.adler32(page_body(file, page)) ~= page.checksum then checksum_errors = checksum_errors + 1 end
                lines[#lines + 1] = 'page ' .. (number - 1) .. ' ' .. column.name .. ' ' .. (page_number - 1) .. ' offset ' .. page.offset .. ' header ' .. page.header_size
                    .. ' body ' .. page.body_size .. ' checksum ' .. checksum_text(page.checksum) .. ' encoding ' .. encoding.methods[page.method] .. ' values ' .. page.count .. ' nulls ' .. page.nulls .. ' ' .. statistics_text(column, page.bounds)
                for _, value in ipairs(decode_page(file, column, page, dictionary)) do
                    cells = cells + 1; if value == NULL then nulls = nulls + 1 end
                    if value ~= original[row][index] then mismatches = mismatches + 1 end; row = row + 1
                end
            end
        end
    end
    for index, column in ipairs(columns) do
        local summary = summaries[index]
        lines[#lines + 1] = 'summary ' .. column.name .. ' bytes ' .. summary.bytes .. ' data_pages ' .. summary.data_pages .. ' dictionary_pages ' .. summary.dictionary_pages .. ' encodings ' .. method_list(keys(summary.methods))
    end
    lines[#lines + 1] = 'roundtrip ' .. (mismatches == 0 and checksum_errors == 0 and 'ok' or 'failed') .. ' cells ' .. cells .. ' nulls ' .. nulls .. ' mismatches ' .. mismatches .. ' checksum_errors ' .. checksum_errors
    return lines
end

local function condition_leaves(tree, leaves)
    leaves = leaves or {}
    if not tree then return leaves end
    if tree.operation == 'NOT' then condition_leaves(tree.child, leaves)
    elseif tree.operation == 'AND' or tree.operation == 'OR' then condition_leaves(tree.left, leaves); condition_leaves(tree.right, leaves)
    else leaves[#leaves + 1] = tree end
    return leaves
end
local function check_query(raw, columns)
    local indices, items = {}, raw.items
    for index, column in ipairs(columns) do indices[column.name] = index end
    if not items then items = {}; for _, column in ipairs(columns) do items[#items + 1] = {operation = 'COLUMN', name = column.name} end end
    local leaves, names = condition_leaves(raw.condition), {}
    for _, item in ipairs(items) do if item.name then names[#names + 1] = item.name end end
    for _, leaf in ipairs(leaves) do names[#names + 1] = leaf.column end
    if raw.group then names[#names + 1] = raw.group end
    if raw.order then names[#names + 1] = raw.order end
    for _, name in ipairs(names) do if not indices[name] then return 'unknown_column' end end
    for _, leaf in ipairs(leaves) do
        local kind = columns[indices[leaf.column]].kind
        local expected = kind == 'DATE' and 'STRING' or kind
        for _, literal in ipairs(leaf.literals) do if literal.kind ~= expected then return 'type_mismatch' end end
    end
    local aggregate = raw.group ~= nil
    for _, item in ipairs(items) do
        if (item.operation == 'SUM' or item.operation == 'AVG') and columns[indices[item.name]].kind ~= 'INT' then return 'bad_aggregate' end
        if item.operation ~= 'COLUMN' then aggregate = true end
    end
    if aggregate then for _, item in ipairs(items) do if item.operation == 'COLUMN' and item.name ~= raw.group then return 'not_grouped' end end end
    if aggregate and raw.order then return 'bad_order' end
    local function convert(tree)
        if not tree then return nil end
        local operation = tree.operation
        if operation == 'NOT' then return {operation = operation, child = convert(tree.child)} end
        if operation == 'AND' or operation == 'OR' then return {operation = operation, left = convert(tree.left), right = convert(tree.right)} end
        local index, values = indices[tree.column], {}
        for position, literal in ipairs(tree.literals) do
            if columns[index].kind == 'DATE' then values[position] = schema.day_number(literal.value) else values[position] = literal.value end
        end
        return {operation = operation, index = index, literals = values}
    end
    local plan_items, headers, needed, condition_columns = {}, {}, {}, {}
    for _, name in ipairs(names) do needed[indices[name]] = true end
    for _, leaf in ipairs(leaves) do condition_columns[indices[leaf.column]] = true end
    for _, item in ipairs(items) do
        local header
        if item.operation == 'COLUMN' then header = item.name
        elseif item.operation == 'COUNT_DISTINCT' then header = 'COUNT(DISTINCT ' .. item.name .. ')'
        else header = item.operation .. '(' .. (item.name or '*') .. ')' end
        headers[#headers + 1] = header; plan_items[#plan_items + 1] = {operation = item.operation, index = item.name and indices[item.name] or nil}
    end
    return nil, {items = plan_items, headers = headers, condition = convert(raw.condition), group = raw.group and indices[raw.group] or nil,
        order = raw.order and indices[raw.order] or nil, descending = raw.descending, limit = raw.limit, aggregate = aggregate,
        needed = keys(needed), condition_columns = keys(condition_columns)}
end
local UNKNOWN_TRUTH = {}
local function logical_not(value) if value == UNKNOWN_TRUTH then return value end; return not value end
local function logical_pair(operation, first, second)
    if operation == 'AND' then
        if first == false or second == false then return false end
        if first == UNKNOWN_TRUTH or second == UNKNOWN_TRUTH then return UNKNOWN_TRUTH end
        return true
    end
    if first == true or second == true then return true end
    if first == UNKNOWN_TRUTH or second == UNKNOWN_TRUTH then return UNKNOWN_TRUTH end
    return false
end
local function compare_value(kind, operation, value, literals)
    if operation == 'IS_NULL' then return value == NULL end
    if operation == 'IS_NOT_NULL' then return value ~= NULL end
    if value == NULL then return UNKNOWN_TRUTH end
    if operation == 'BETWEEN' then return not schema.less(kind, value, literals[1]) and not schema.less(kind, literals[2], value) end
    if operation == 'IN' then for _, literal in ipairs(literals) do if literal == value then return true end end; return false end
    local other = literals[1]
    if operation == '=' then return value == other elseif operation == '<>' then return value ~= other
    elseif operation == '<' then return schema.less(kind, value, other) elseif operation == '<=' then return not schema.less(kind, other, value)
    elseif operation == '>' then return schema.less(kind, other, value) else return not schema.less(kind, value, other) end
end
local evaluate
evaluate = function(tree, row, columns)
    if not tree then return true end
    if tree.operation == 'NOT' then return logical_not(evaluate(tree.child, row, columns)) end
    if tree.operation == 'AND' or tree.operation == 'OR' then return logical_pair(tree.operation, evaluate(tree.left, row, columns), evaluate(tree.right, row, columns)) end
    return compare_value(columns[tree.index].kind, tree.operation, row[tree.index], tree.literals)
end
local function range_possibilities(kind, operation, bounds, literals)
    local low, high = bounds[1], bounds[2]
    local function less(a, b) return schema.less(kind, a, b) end
    local function le(a, b) return not less(b, a) end
    if operation == 'BETWEEN' then return le(low, literals[2]) and le(literals[1], high) and le(literals[1], literals[2]), less(low, literals[1]) or less(literals[2], high) end
    if operation == 'IN' then
        local possible, same = false, false
        for _, literal in ipairs(literals) do if le(low, literal) and le(literal, high) then possible = true end; if low == literal then same = true end end
        return possible, not (low == high and same)
    end
    local value = literals[1]
    if operation == '=' then return le(low, value) and le(value, high), not (low == value and high == value)
    elseif operation == '<>' then return not (low == value and high == value), le(low, value) and le(value, high)
    elseif operation == '<' then return less(low, value), le(value, high)
    elseif operation == '<=' then return le(low, value), less(value, high)
    elseif operation == '>' then return less(value, high), le(low, value)
    else return le(value, high), less(low, value) end
end
local zone_values
zone_values = function(tree, zones, columns)
    local operation, values = tree.operation, {}
    if operation == 'NOT' then for value in pairs(zone_values(tree.child, zones, columns)) do values[logical_not(value)] = true end; return values end
    if operation == 'AND' or operation == 'OR' then
        local first, second = zone_values(tree.left, zones, columns), zone_values(tree.right, zones, columns)
        for a in pairs(first) do for b in pairs(second) do values[logical_pair(operation, a, b)] = true end end
        return values
    end
    local zone = zones[tree.index]
    if operation == 'IS_NULL' or operation == 'IS_NOT_NULL' then
        if zone.nulls > 0 then values[operation == 'IS_NULL'] = true end
        if zone.nulls < zone.rows then values[operation == 'IS_NOT_NULL'] = true end
        return values
    end
    if zone.nulls > 0 then values[UNKNOWN_TRUTH] = true end
    if zone.bounds then
        local can_be_true, can_be_false = range_possibilities(columns[tree.index].kind, operation, zone.bounds, tree.literals)
        if can_be_true then values[true] = true end; if can_be_false then values[false] = true end
    end
    return values
end

local function read_scan_page(file, group_number, column_index, page_number, dictionaries, counts)
    local column, chunk = file.columns[column_index], file.groups[group_number].chunks[column_index]
    local page, dictionary = chunk.pages[page_number], nil
    if page.method == 1 then
        local key = group_number .. ':' .. column_index
        if dictionaries[key] == nil then
            dictionaries[key] = decode_dictionary(file, column, chunk.dictionary)
            counts.dictionary_pages_read, counts.bytes_read = counts.dictionary_pages_read + 1, counts.bytes_read + chunk.dictionary.size
        end
        dictionary = dictionaries[key]
    end
    counts.pages_read, counts.bytes_read = counts.pages_read + 1, counts.bytes_read + page.size
    return decode_page(file, column, page, dictionary)
end
local function empty_row(columns) local row = {}; for index = 1, #columns do row[index] = NULL end; return row end
local function scan(file, plan)
    local counts, records, matched, dictionaries, condition_set, remaining = counter(), {}, {}, {}, {}, {}
    for _, index in ipairs(plan.condition_columns) do condition_set[index] = true end
    for _, index in ipairs(plan.needed) do if not condition_set[index] then remaining[#remaining + 1] = index end end
    for group_number, group in ipairs(file.groups) do
        local zones = {}
        for _, index in ipairs(plan.condition_columns) do local chunk = group.chunks[index]; zones[index] = {bounds = chunk.bounds, nulls = chunk.nulls, rows = group.rows} end
        if plan.condition and not zone_values(plan.condition, zones, file.columns)[true] then
            counts.row_groups_skipped, records[group_number] = counts.row_groups_skipped + 1, false
        else
            counts.row_groups_read = counts.row_groups_read + 1
            if #plan.needed == 0 then
                counts.rows_scanned = counts.rows_scanned + group.rows
                for _ = 1, group.rows do matched[#matched + 1] = empty_row(file.columns) end
                records[group_number] = '-'
            else
                local record = {}
                for page_number = 1, group.chunks[1].page_count do
                    zones = {}
                    for _, index in ipairs(plan.condition_columns) do
                        local page = group.chunks[index].pages[page_number]; zones[index] = {bounds = page.bounds, nulls = page.nulls, rows = page.count}
                    end
                    if plan.condition and not zone_values(plan.condition, zones, file.columns)[true] then
                        counts.pages_skipped = counts.pages_skipped + #plan.needed; record[#record + 1] = 's'
                    else
                        local row_count, rows, selected = group.chunks[1].pages[page_number].count, {}, {}
                        counts.rows_scanned = counts.rows_scanned + row_count
                        for index = 1, row_count do rows[index] = empty_row(file.columns) end
                        for _, index in ipairs(plan.condition_columns) do
                            local values = read_scan_page(file, group_number, index, page_number, dictionaries, counts)
                            for row = 1, row_count do rows[row][index] = values[row] end
                        end
                        for row, values in ipairs(rows) do if evaluate(plan.condition, values, file.columns) == true then selected[#selected + 1] = row end end
                        if #selected == 0 and #remaining > 0 then counts.pages_unneeded = counts.pages_unneeded + #remaining; record[#record + 1] = 'u'
                        else
                            for _, index in ipairs(remaining) do
                                local values = read_scan_page(file, group_number, index, page_number, dictionaries, counts)
                                for row = 1, row_count do rows[row][index] = values[row] end
                            end
                            for _, row in ipairs(selected) do matched[#matched + 1] = rows[row] end
                            record[#record + 1] = 'r'
                        end
                    end
                end
                records[group_number] = table.concat(record)
            end
        end
    end
    counts.rows_matched = #matched
    return matched, counts, records
end
local function gcd(first, second)
    local a, b = math.abs(first), math.abs(second); while b ~= 0 do a, b = b, a % b end; return a
end
local function aggregate_item(columns, item, rows, key)
    local operation, index = item.operation, item.index
    if operation == 'COLUMN' then return schema.value_text(columns[index].kind, key) end
    if operation == 'COUNT' and index == nil then return tostring(#rows) end
    local values = {}; for _, row in ipairs(rows) do if row[index] ~= NULL then values[#values + 1] = row[index] end end
    if operation == 'COUNT' then return tostring(#values) end
    if operation == 'COUNT_DISTINCT' then local seen, count = {}, 0; for _, value in ipairs(values) do if not seen[value] then seen[value], count = true, count + 1 end end; return tostring(count) end
    if #values == 0 then return 'NULL' end
    if operation == 'SUM' or operation == 'AVG' then
        local total = 0; for _, value in ipairs(values) do total = total + value end
        if operation == 'SUM' then return tostring(total) end
        local divisor = gcd(total, #values); local numerator, denominator = total // divisor, #values // divisor
        return denominator == 1 and tostring(numerator) or numerator .. '/' .. denominator
    end
    local selected, kind = values[1], columns[index].kind
    for position = 2, #values do
        local value = values[position]
        if operation == 'MIN' and schema.less(kind, value, selected) or operation == 'MAX' and schema.less(kind, selected, value) then selected = value end
    end
    return schema.value_text(kind, selected)
end
local function build_result(columns, plan, matched)
    local kind, output = nil, {}
    if not plan.aggregate then
        kind = 'rows'
        local arranged = {}; for index, row in ipairs(matched) do arranged[index] = {row = row, order = index} end
        if plan.order then
            local index, column_kind = plan.order, columns[plan.order].kind
            table.sort(arranged, function(a, b)
                local left, right = a.row[index], b.row[index]
                if left == right then return a.order < b.order end
                if plan.descending then return schema.less(column_kind, right, left) end
                return schema.less(column_kind, left, right)
            end)
        end
        for _, entry in ipairs(arranged) do
            local parts = {}; for _, item in ipairs(plan.items) do parts[#parts + 1] = schema.value_text(columns[item.index].kind, entry.row[item.index]) end
            output[#output + 1] = table.concat(parts, ',')
        end
    else
        local groups = {}
        if plan.group then
            kind = 'grouped'
            local grouped, group_keys = {}, {}
            for _, row in ipairs(matched) do
                local key = row[plan.group]
                if not grouped[key] then grouped[key] = {}; group_keys[#group_keys + 1] = key end
                grouped[key][#grouped[key] + 1] = row
            end
            table.sort(group_keys, function(a, b) return schema.less(columns[plan.group].kind, a, b) end)
            for _, key in ipairs(group_keys) do groups[#groups + 1] = {key = key, rows = grouped[key]} end
        else kind, groups = 'aggregate', {{key = NULL, rows = matched}} end
        for _, group in ipairs(groups) do
            local parts = {}; for _, item in ipairs(plan.items) do parts[#parts + 1] = aggregate_item(columns, item, group.rows, group.key) end
            output[#output + 1] = table.concat(parts, ',')
        end
    end
    if plan.limit and #output > plan.limit then output = slice(output, 1, plan.limit) end
    return {kind = kind, matched = #matched, output = output}
end
local function same_result(first, second)
    if first.kind ~= second.kind or first.matched ~= second.matched or #first.output ~= #second.output then return false end
    for index, row in ipairs(first.output) do if row ~= second.output[index] then return false end end
    return true
end
local function counts_text(counts)
    local parts = {}; for _, name in ipairs(scan_names) do parts[#parts + 1] = name .. ' ' .. counts[name] end; return table.concat(parts, ' ')
end
local function execute_queries(file, original, queries)
    local results, statistics_lines, totals, errors, checks_ok = {}, {}, counter(), 0, 0
    for number, text in ipairs(queries) do
        local failure, plan = check_query(QueryParser.new(text):parse(), file.columns)
        if failure then
            local line = 'query ' .. number .. ' error ' .. failure; results[#results + 1], statistics_lines[#statistics_lines + 1], errors = line, line, errors + 1
        else
            local matched, counts, records = scan(file, plan)
            local result, reference = build_result(file.columns, plan, matched), {}
            for _, row in ipairs(original) do if evaluate(plan.condition, row, file.columns) == true then reference[#reference + 1] = row end end
            local check = same_result(result, build_result(file.columns, plan, reference)) and 'ok' or 'mismatch'
            if check == 'ok' then checks_ok = checks_ok + 1 end
            results[#results + 1] = 'query ' .. number .. ' ' .. result.kind .. ' matched ' .. result.matched .. ' output ' .. #result.output
            results[#results + 1] = 'columns ' .. table.concat(plan.headers, ','); append(results, result.output)
            local needed = {}; for _, index in ipairs(plan.needed) do needed[#needed + 1] = file.columns[index].name end
            statistics_lines[#statistics_lines + 1] = 'query ' .. number .. ' columns ' .. (#needed > 0 and table.concat(needed, ',') or '-') .. ' ' .. counts_text(counts) .. ' check ' .. check
            for group, record in ipairs(records) do statistics_lines[#statistics_lines + 1] = 'query ' .. number .. ' row_group ' .. (group - 1) .. ' ' .. (record == false and 'skipped' or 'pages ' .. record) end
            for _, name in ipairs(scan_names) do totals[name] = totals[name] + counts[name] end
        end
    end
    statistics_lines[#statistics_lines + 1] = 'total queries ' .. #queries .. ' errors ' .. errors .. ' ' .. counts_text(totals) .. ' checks_ok ' .. checks_ok
    return results, statistics_lines
end
local function recover(data)
    local file = parse_file(data)
    local columns, rows = file.columns, {}
    for row = 1, file.rows do rows[row] = {}; for column = 1, #columns do rows[row][column] = UNKNOWN end end
    local lines = {'file bytes ' .. #data .. ' rows ' .. file.rows .. ' columns ' .. #columns .. ' row_groups ' .. #file.groups}
    for index, column in ipairs(columns) do lines[#lines + 1] = column_line(index - 1, column) end
    local examined, damaged_count, lost_pages, lost_cells = 0, 0, 0, 0
    for group_number, group in ipairs(file.groups) do
        for index, column in ipairs(columns) do
            local chunk, dictionary, dictionary_damaged, pages = group.chunks[index], nil, false, {}
            if chunk.dictionary then pages[#pages + 1] = {number = 'dict', page = chunk.dictionary} end
            for number, page in ipairs(chunk.pages) do pages[#pages + 1] = {number = tostring(number - 1), page = page} end
            local row_number = group.first_row + 1
            for _, entry in ipairs(pages) do
                local page = entry.page; examined = examined + 1
                local checksum = bits.adler32(page_body(file, page))
                local damaged = checksum ~= page.checksum
                if damaged then
                    damaged_count = damaged_count + 1
                    lines[#lines + 1] = 'damaged ' .. (group_number - 1) .. ' ' .. column.name .. ' ' .. entry.number .. ' offset ' .. page.offset .. ' stored ' .. checksum_text(page.checksum) .. ' computed ' .. checksum_text(checksum)
                end
                if entry.number == 'dict' then
                    dictionary_damaged = damaged
                    if not damaged then dictionary = decode_dictionary(file, column, page) end
                else
                    local reason
                    if damaged then reason = 'checksum' elseif page.method == 1 and dictionary_damaged then reason = 'dictionary' end
                    if reason then
                        lost_pages, lost_cells = lost_pages + 1, lost_cells + page.count
                        lines[#lines + 1] = 'lost ' .. (group_number - 1) .. ' ' .. column.name .. ' ' .. entry.number .. ' rows ' .. page.count .. ' reason ' .. reason
                    else for offset, value in ipairs(decode_page(file, column, page, dictionary)) do rows[row_number + offset - 1][index] = value end end
                    row_number = row_number + page.count
                end
            end
        end
    end
    lines[#lines + 1] = 'summary pages ' .. examined .. ' damaged ' .. damaged_count .. ' lost_pages ' .. lost_pages .. ' lost_cells ' .. lost_cells .. ' recovered_cells ' .. (file.rows * #columns - lost_cells)
    local names, recovered = {}, {}; for _, column in ipairs(columns) do names[#names + 1] = column.name end; recovered[1] = table.concat(names, ',')
    for _, row in ipairs(rows) do
        local fields = {}; for index, column in ipairs(columns) do fields[index] = schema.value_text(column.kind, row[index], '') end
        recovered[#recovered + 1] = table.concat(fields, ',')
    end
    return lines, recovered
end

local columns, rows, options, queries, damaged = schema.read_inputs()
local data, encoding_report = build_file(columns, rows, options)
local file = parse_file(data)
local metadata = verify_and_describe(file, rows)
local query_results, query_statistics = execute_queries(file, rows, queries)
local recovery, recovered = recover(damaged)
local hex_lines = {}; for first = 1, #data, 32 do hex_lines[#hex_lines + 1] = hex(slice(data, first, math.min(first + 31, #data))) end
schema.write_outputs({['file.hex'] = hex_lines, ['metadata.txt'] = metadata, ['encoding_report.csv'] = encoding_report,
    ['query_results.txt'] = query_results, ['query_stats.txt'] = query_statistics, ['recovery.txt'] = recovery, ['recovered.csv'] = recovered})
