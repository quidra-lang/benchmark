local M = {}
function M.object(number, pointers, data)
    local fields = {}
    for i = 1, pointers do
        fields[i] = 0
    end
    return {number = number, size = 1 + pointers + data, fields = fields, address = 0, marked = false, moves = 0, age = 0, count = 0, present = true}
end
function M.pair()
    return {count = 0, words = 0}
end
function M.add(pair, object)
    pair.count, pair.words = pair.count + 1, pair.words + object.size
end
function M.add_pair(pair, other)
    pair.count, pair.words = pair.count + other.count, pair.words + other.words
end
function M.pair_text(pair)
    return pair.count .. " " .. pair.words
end
function M.active(state)
    local objects = {}
    for _, object in ipairs(state.objects) do
        if object.present then
            objects[#objects + 1] = object
        end
    end
    return objects
end
function M.by_address(objects)
    local ordered = {table.unpack(objects)}
    table.sort(ordered, function(a, b)
        return a.address < b.address
    end)
    return ordered
end
function M.free_blocks(objects, start, finish)
    local blocks, position = {}, start
    for _, object in ipairs(M.by_address(objects)) do
        if object.address >= start and object.address < finish then
            if object.address > position then
                blocks[#blocks + 1] = {address = position, length = object.address - position}
            end
            position = object.address + object.size
        end
    end
    if position < finish then
        blocks[#blocks + 1] = {address = position, length = finish - position}
    end
    return blocks
end
function M.first_fit(blocks, size)
    for _, block in ipairs(blocks) do
        if block.length >= size then
            return block.address
        end
    end
end
function M.total_free(blocks)
    local total = 0
    for _, block in ipairs(blocks) do
        total = total + block.length
    end
    return total
end
function M.largest_free(blocks)
    local largest = 0
    for _, block in ipairs(blocks) do
        largest = math.max(largest, block.length)
    end
    return largest
end
function M.dec2(numerator, denominator)
    local rounded = (200 * numerator + denominator) // (2 * denominator)
    return string.format("%d.%02d", rounded // 100, rounded % 100)
end
function M.pct(part, whole)
    return whole == 0 and "-" or M.dec2(100 * part, whole)
end
function M.class_table(values)
    local counts = {0, 0, 0, 0, 0}
    for _, value in ipairs(values) do
        local index = value == 1 and 1 or value <= 3 and 2 or value <= 7 and 3 or value <= 15 and 4 or 5
        counts[index] = counts[index] + 1
    end
    return string.format("1:%d 2-3:%d 4-7:%d 8-15:%d 16+:%d", table.unpack(counts))
end
function M.state(size, entry)
    return {size = size, algorithm = entry.algorithm, young = entry.young, half = (entry.algorithm == "GENERATIONAL" and entry.young or size) // 2, promotion_age = entry.age, base = 0, top = 0, target = 0, objects = {}, records = {}, remembered = {}, barriers = 0, remembers = 0}
end
function M.free_list(state)
    if state.algorithm == "MARK_COMPACT" then
        return state.top < state.size and {{address = state.top, length = state.size - state.top}} or {}
    end
    if state.algorithm == "COPYING" or state.algorithm == "GENERATIONAL" then
        local blocks, finish = {}, state.base + state.half
        if state.top < finish then
            blocks[1] = {address = state.top, length = finish - state.top}
        end
        if state.algorithm == "GENERATIONAL" then
            for _, block in ipairs(M.free_blocks(M.active(state), state.young, state.size)) do
                blocks[#blocks + 1] = block
            end
        end
        return blocks
    end
    return M.free_blocks(M.active(state), 0, state.size)
end
function M.record(state, line, request, kind)
    local blocks = M.free_list(state)
    return {number = #state.records + 1, line = line, request = request, kind = kind, live = M.pair(), freed = M.pair(), moved = M.pair(), promoted = M.pair(), stack = 0, work = 0, before = {M.total_free(blocks), M.largest_free(blocks)}}
end
function M.finish(state, record)
    local blocks = M.free_list(state)
    record.after = {M.total_free(blocks), M.largest_free(blocks)}
    state.records[#state.records + 1] = record
end
function M.heap_map(state, reached)
    local cells = {}
    for i = 1, state.size do
        cells[i] = "."
    end
    if state.algorithm == "COPYING" or state.algorithm == "GENERATIONAL" then
        local start = state.half - state.base
        for address = start, start + state.half - 1 do
            cells[address + 1] = "-"
        end
    end
    for _, object in ipairs(M.active(state)) do
        local letter = string.char(65 + (object.number - 1) % 26)
        local header, body = reached[object.number] and letter or "#", reached[object.number] and letter:lower() or "="
        cells[object.address + 1] = header
        for address = object.address + 1, object.address + object.size - 1 do
            cells[address + 1] = body
        end
    end
    return table.concat(cells)
end
return M
