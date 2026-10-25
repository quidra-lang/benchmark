local transposition = {}

function transposition.rail(position, rails)
    local cycle = 2 * rails - 2
    local offset = position % cycle
    return math.min(offset, cycle - offset)
end

function transposition.rail_fence(text, rails, encrypt)
    local order, result = {}, {}
    for i = 1, #text do
        order[i] = i
    end
    table.sort(order, function(a, b)
        local first = transposition.rail(a - 1, rails)
        local second = transposition.rail(b - 1, rails)
        return first == second and a < b or first < second
    end)
    for i, position in ipairs(order) do
        if encrypt then
            result[i] = text:sub(position, position)
        else
            result[position] = text:sub(i, i)
        end
    end
    return table.concat(result)
end

function transposition.column_order(key)
    local order = {}
    for i = 1, #key do
        order[i] = i
    end
    table.sort(order, function(a, b)
        local first = key:sub(a, a)
        local second = key:sub(b, b)
        return first == second and a < b or first < second
    end)
    return order
end

function transposition.rank_string(key)
    local ranks = {}
    for position, column in ipairs(transposition.column_order(key)) do
        ranks[column] = tostring(position)
    end
    return table.concat(ranks)
end

function transposition.columnar(text, key, encrypt)
    local result, pointer = {}, 1
    for _, column in ipairs(transposition.column_order(key)) do
        for position = column, #text, #key do
            if encrypt then
                result[pointer] = text:sub(position, position)
            else
                result[position] = text:sub(pointer, pointer)
            end
            pointer = pointer + 1
        end
    end
    return table.concat(result)
end

return transposition
