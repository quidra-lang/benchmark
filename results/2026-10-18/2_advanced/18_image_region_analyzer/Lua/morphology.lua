local M = {}
local neighborhood = {{0, -1}, {1, -1}, {1, 0}, {1, 1}, {0, 1}, {-1, 1}, {-1, 0}, {-1, -1}}

function M.key(x, y) return x .. "," .. y end

local function occupied(mask, x, y)
    return y >= 0 and y < #mask and x >= 0 and x < #mask[y + 1] and mask[y + 1][x + 1]
end

function M.erode(mask, offsets)
    local result = {}
    for y = 0, #mask - 1 do
        local row = {}
        for x = 0, #mask[y + 1] - 1 do
            local foreground = true
            for _, offset in ipairs(offsets) do
                if not occupied(mask, x + offset[1], y + offset[2]) then foreground = false break end
            end
            row[x + 1] = foreground
        end
        result[y + 1] = row
    end
    return result
end

function M.dilate(mask, offsets)
    local result = {}
    for y = 0, #mask - 1 do
        local row = {}
        for x = 0, #mask[y + 1] - 1 do
            local foreground = false
            for _, offset in ipairs(offsets) do
                if occupied(mask, x - offset[1], y - offset[2]) then foreground = true break end
            end
            row[x + 1] = foreground
        end
        result[y + 1] = row
    end
    return result
end

function M.opening(mask, offsets) return M.dilate(M.erode(mask, offsets), offsets) end
function M.closing(mask, offsets) return M.erode(M.dilate(mask, offsets), offsets) end

function M.neighbor_bits(pixels, x, y)
    local bits = {}
    for index, offset in ipairs(neighborhood) do
        bits[index] = pixels[M.key(x + offset[1], y + offset[2])] ~= nil
    end
    return bits
end

function M.transitions(bits)
    local count = 0
    for index = 1, 8 do
        if not bits[index] and bits[index % 8 + 1] then count = count + 1 end
    end
    return count
end

function M.crossing_number(pixels, x, y) return M.transitions(M.neighbor_bits(pixels, x, y)) end

local function removable(bits, first_step)
    local count = 0
    for _, bit in ipairs(bits) do if bit then count = count + 1 end end
    if count < 2 or count > 6 or M.transitions(bits) ~= 1 then return false end
    local p2, p4, p6, p8 = bits[1], bits[3], bits[5], bits[7]
    if first_step then return not (p2 and p4 and p6) and not (p4 and p6 and p8) end
    return not (p2 and p4 and p8) and not (p2 and p6 and p8)
end

local function thinning_step(skeleton, first_step)
    local removed = {}
    for key, point in pairs(skeleton) do
        if removable(M.neighbor_bits(skeleton, point[1], point[2]), first_step) then
            removed[#removed + 1] = key
        end
    end
    for _, key in ipairs(removed) do skeleton[key] = nil end
    return #removed > 0
end

function M.thin(pixels)
    local skeleton = {}
    for _, point in ipairs(pixels) do skeleton[M.key(point[1], point[2])] = point end
    while true do
        local first = thinning_step(skeleton, true)
        local second = thinning_step(skeleton, false)
        if not first and not second then return skeleton end
    end
end

return M
