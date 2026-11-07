local Crossing = require("crossing")
local Coordinates = {}
Coordinates.variants = {"ul", "ur", "dl", "dr"}

local function segment(a, b)
    return a .. ":" .. b
end

local function mark_conflicts(orders, upper, node_count, position)
    local marked = {}
    for layer = 1, #orders - 1 do
        local above, below, first_bound, start = orders[layer], orders[layer + 1], 0, 1
        for last, vertex in ipairs(below) do
            local inner = vertex > node_count and upper[vertex][1] > node_count
            if inner or last == #below then
                local last_bound = inner and position[upper[vertex][1]] or #above - 1
                for index = start, last do
                    local following = below[index]
                    for _, previous in ipairs(upper[following]) do
                        if position[previous] < first_bound or position[previous] > last_bound then marked[segment(previous, following)] = true end
                    end
                end
                start, first_bound = last + 1, last_bound
            end
        end
    end
    return marked
end

local function alignment(variant, orders, upper, lower, marked, count)
    local leftward, upward = variant:sub(2, 2) == "l", variant:sub(1, 1) == "u"
    local scan, root, align = {}, {}, {}
    for layer, vertices in ipairs(orders) do
        scan[layer] = {}
        for i = 1, #vertices do scan[layer][i] = vertices[leftward and i or #vertices - i + 1] end
    end
    local rank = Crossing.positions(scan)
    for i = 1, count do root[i], align[i] = i, i end
    local reference = upward and upper or lower
    for step = 2, #orders do
        local layer = upward and step or #orders - step + 1
        local boundary = -1
        for _, vertex in ipairs(scan[layer]) do
            local neighbors = {}
            for i, neighbor in ipairs(reference[vertex]) do neighbors[i] = neighbor end
            table.sort(neighbors, function(a, b) return rank[a] < rank[b] end)
            if #neighbors > 0 then
                for _, middle in ipairs({(#neighbors - 1) // 2 + 1, #neighbors // 2 + 1}) do
                    local neighbor = neighbors[middle]
                    local key = upward and segment(neighbor, vertex) or segment(vertex, neighbor)
                    if align[vertex] == vertex and not marked[key] and boundary < rank[neighbor] then
                        align[neighbor], root[vertex] = vertex, root[neighbor]
                        align[vertex], boundary = root[vertex], rank[neighbor]
                    end
                end
            end
        end
    end
    return root, scan
end

local function compact(root, scan, variant, left, right, node_count, settings)
    local blocks, outgoing, incoming = {}, {}, {}
    for _, block in ipairs(root) do if not outgoing[block] then blocks[#blocks + 1], outgoing[block], incoming[block] = block, {}, {} end end
    table.sort(blocks)
    for _, layer in ipairs(scan) do
        for index = 1, #layer - 1 do
            local first, second = layer[index], layer[index + 1]
            local a, b = first, second
            if variant:sub(2, 2) == "r" then a, b = second, first end
            local gap = a <= node_count and b <= node_count and settings.node_sep or settings.dummy_sep
            local distance = right[a] + left[b] + 1 + gap
            local origin, target = root[first], root[second]
            distance = math.max(distance, outgoing[origin][target] or distance)
            outgoing[origin][target], incoming[target][origin] = distance, distance
        end
    end
    local pending, ready, ordered, first_coordinate, second_coordinate = {}, {}, {}, {}, {}
    for _, block in ipairs(blocks) do
        local count = 0
        for _ in pairs(incoming[block]) do count = count + 1 end
        pending[block] = count
        if count == 0 then ready[#ready + 1] = block end
    end
    while #ready > 0 do
        local block, coordinate = table.remove(ready), 0
        ordered[#ordered + 1] = block
        for previous, distance in pairs(incoming[block]) do coordinate = math.max(coordinate, first_coordinate[previous] + distance) end
        first_coordinate[block] = coordinate
        for following in pairs(outgoing[block]) do
            pending[following] = pending[following] - 1
            if pending[following] == 0 then ready[#ready + 1] = following end
        end
    end
    for i = #ordered, 1, -1 do
        local block = ordered[i]
        local coordinate, minimum = first_coordinate[block], nil
        for following, distance in pairs(outgoing[block]) do
            local value = second_coordinate[following] - distance
            minimum = minimum and math.min(minimum, value) or value
        end
        if minimum then coordinate = math.max(coordinate, minimum) end
        second_coordinate[block] = coordinate
    end
    local result, sign = {}, variant:sub(2, 2) == "l" and 1 or -1
    for i, block in ipairs(root) do result[i] = sign * second_coordinate[block] end
    return result, #blocks
end

function Coordinates.assign(orders, upper, lower, widths, node_count, settings)
    local count, left, right = #widths, {}, {}
    local vertical = settings.direction == "TB" or settings.direction == "BT"
    for i, width in ipairs(widths) do
        left[i] = vertical and (width - 1) // 2 or 0
        right[i] = vertical and width - 1 - left[i] or 0
    end
    local conflicts = mark_conflicts(orders, upper, node_count, Crossing.positions(orders))
    local layouts, blocks, bounds, spans, smallest = {}, {}, {}, {}, nil
    for _, variant in ipairs(Coordinates.variants) do
        local root, scan = alignment(variant, orders, upper, lower, conflicts, count)
        local layout, block_count = compact(root, scan, variant, left, right, node_count, settings)
        local low, high = math.maxinteger, math.mininteger
        for i, value in ipairs(layout) do low, high = math.min(low, value - left[i]), math.max(high, value + right[i]) end
        layouts[variant], blocks[variant], bounds[variant], spans[variant] = layout, block_count, {low, high}, high - low + 1
        if not smallest or spans[variant] < spans[smallest] then smallest = variant end
    end
    local aligned, x = {}, {}
    for _, variant in ipairs(Coordinates.variants) do
        local side = variant:sub(2, 2) == "l" and 1 or 2
        local shift = bounds[smallest][side] - bounds[variant][side]
        aligned[variant] = {}
        for i, value in ipairs(layouts[variant]) do aligned[variant][i] = value + shift end
    end
    local low = math.maxinteger
    for vertex = 1, count do
        local values = {}
        for i, variant in ipairs(Coordinates.variants) do values[i] = aligned[variant][vertex] end
        table.sort(values)
        x[vertex] = (values[2] + values[3]) // 2
        low = math.min(low, x[vertex] - left[vertex])
    end
    for i = 1, count do x[i] = x[i] - low end
    return {x = x, left = left, right = right, aligned = aligned, blocks = blocks, widths = spans, smallest = smallest, conflicts = conflicts}
end

return Coordinates
