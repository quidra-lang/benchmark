local schema = {types = {'INT', 'STRING', 'BOOL', 'DATE'}, NULL = {}, UNKNOWN = {}}
function schema.split(text, separator)
    local values, start = {}, 1
    while true do
        local position = text:find(separator, start, true)
        if not position then values[#values + 1] = text:sub(start); return values end
        values[#values + 1] = text:sub(start, position - 1); start = position + #separator
    end
end
local function leap(year) return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0) end
local function months(year) return {31, leap(year) and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31} end
local function before_year(year) local y = year - 1; return 365 * y + y // 4 - y // 100 + y // 400 end
function schema.day_number(text)
    local y, m, d = text:match('^(%d+)%-(%d+)%-(%d+)$')
    local year, month, day = tonumber(y), tonumber(m), tonumber(d)
    local days, lengths = before_year(year) - before_year(1970) + day - 1, months(year)
    for index = 1, month - 1 do days = days + lengths[index] end
    return days
end
local function date_text(day)
    local year = 1970
    while day < 0 do year = year - 1; day = day + (leap(year) and 366 or 365) end
    while day >= (leap(year) and 366 or 365) do day = day - (leap(year) and 366 or 365); year = year + 1 end
    local month = 1
    for _, length in ipairs(months(year)) do if day < length then break end; day = day - length; month = month + 1 end
    return string.format('%04d-%02d-%02d', year, month, day + 1)
end
function schema.parse_value(kind, field)
    if field == '' then return schema.NULL end
    if kind == 'INT' then return tonumber(field) end
    if kind == 'DATE' then return schema.day_number(field) end
    if kind == 'BOOL' then return field == 'true' end
    return field
end
function schema.value_text(kind, value, null)
    if value == schema.NULL then return null or 'NULL' end
    if value == schema.UNKNOWN then return '?' end
    if kind == 'DATE' then return date_text(value) end
    if kind == 'BOOL' then return value and 'true' or 'false' end
    return tostring(value)
end
function schema.less(kind, a, b)
    if a == schema.NULL then return b ~= schema.NULL end
    if b == schema.NULL then return false end
    if kind == 'BOOL' then return a == false and b == true end
    return a < b
end
function schema.read_lines(path)
    local lines = {}; for line in io.lines(path) do lines[#lines + 1] = line end; return lines
end
function schema.read_inputs()
    local columns, rows, options = {}, {}, {encoding = {}}
    for _, line in ipairs(schema.read_lines('input/schema.txt')) do
        local f = schema.split(line, ' '); columns[#columns + 1] = {name = f[1], kind = f[2], nullable = f[3] == 'NULLABLE'}
    end
    local lines = schema.read_lines('input/table.csv')
    for index = 2, #lines do
        local fields, row = schema.split(lines[index], ','), {}
        for column, definition in ipairs(columns) do row[column] = schema.parse_value(definition.kind, fields[column]) end
        rows[#rows + 1] = row
    end
    for _, line in ipairs(schema.read_lines('input/options.txt')) do
        local f = schema.split(line, ' ')
        if f[1] == 'encoding' then options.encoding[f[2]] = f[3] else options[f[1]] = tonumber(f[2]) end
    end
    local hex, damaged = table.concat(schema.read_lines('input/damaged.hex')), {}
    for index = 1, #hex, 2 do damaged[#damaged + 1] = tonumber(hex:sub(index, index + 1), 16) end
    return columns, rows, options, schema.read_lines('input/queries.txt'), damaged
end
function schema.write_outputs(outputs)
    os.execute('mkdir -p output')
    for name, lines in pairs(outputs) do
        local file = assert(io.open('output/' .. name, 'w'))
        file:write(table.concat(lines, '\n'), #lines > 0 and '\n' or ''); file:close()
    end
end
return schema
