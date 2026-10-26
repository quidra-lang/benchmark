local M = {}
local previous = {[4] = {{-1, 0}, {0, -1}}, [8] = {{-1, 0}, {-1, -1}, {0, -1}, {1, -1}}}

local function find(parents, label)
    while parents[label] ~= label do
        parents[label] = parents[parents[label]]
        label = parents[label]
    end
    return label
end

local function union(parents, first, second)
    local a, b = find(parents, first), find(parents, second)
    if a ~= b then parents[math.max(a, b)] = math.min(a, b) end
end

function M.label_components(mask, connectivity)
    local height, width = #mask, #mask[1]
    local provisional, parents, created = {}, {[0] = 0}, 0
    for y = 0, height - 1 do
        local row = {}
        for x = 1, width do row[x] = 0 end
        provisional[y + 1] = row
        for x = 0, width - 1 do
            if mask[y + 1][x + 1] then
                local neighbors = {}
                for _, offset in ipairs(previous[connectivity]) do
                    local nx, ny = x + offset[1], y + offset[2]
                    if nx >= 0 and nx < width and ny >= 0 and mask[ny + 1][nx + 1] then
                        neighbors[#neighbors + 1] = provisional[ny + 1][nx + 1]
                    end
                end
                if #neighbors == 0 then
                    created = created + 1
                    parents[created], row[x + 1] = created, created
                else
                    row[x + 1] = neighbors[1]
                    for index = 2, #neighbors do union(parents, neighbors[1], neighbors[index]) end
                end
            end
        end
    end
    local labels, numbers, count = {}, {}, 0
    for y = 1, height do
        local row = {}
        for x = 1, width do
            row[x] = 0
            if provisional[y][x] ~= 0 then
                local root = find(parents, provisional[y][x])
                if numbers[root] == nil then count = count + 1 numbers[root] = count end
                row[x] = numbers[root]
            end
        end
        labels[y] = row
    end
    return {labels = labels, count = count, provisional = created}
end

local function occupied(mask, x, y)
    return y >= 0 and y < #mask and x >= 0 and x < #mask[y + 1] and mask[y + 1][x + 1]
end

function M.bit_quad_euler(mask, connectivity)
    local singles, triples, diagonals = 0, 0, 0
    for y = -1, #mask - 1 do
        for x = -1, #mask[1] - 1 do
            local a, b = occupied(mask, x, y), occupied(mask, x + 1, y)
            local c, d = occupied(mask, x, y + 1), occupied(mask, x + 1, y + 1)
            local count = (a and 1 or 0) + (b and 1 or 0) + (c and 1 or 0) + (d and 1 or 0)
            if count == 1 then singles = singles + 1
            elseif count == 3 then triples = triples + 1
            elseif count == 2 and (a and d or b and c) then diagonals = diagonals + 1 end
        end
    end
    return (singles - triples + (connectivity == 8 and -2 or 2) * diagonals) // 4
end

return M
