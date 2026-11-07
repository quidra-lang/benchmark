local M = {}
function M.digest(text)
    local parts = {}
    for i, base in ipairs({1000003, 1500007, 2750159, 4194301}) do
        local h = ({11, 23, 37, 53})[i]
        for j = 1, #text do
            h = (h * base + text:byte(j)) % 2147483647
        end
        for _, extra in ipairs({#text, 0, 0}) do
            h = (h * base + extra) % 2147483647
        end
        parts[i] = string.format("%08x", h)
    end
    return table.concat(parts)
end
function M.merkle_root(hashes)
    local level = {table.unpack(hashes)}
    while #level > 1 do
        if #level % 2 == 1 then
            level[#level + 1] = level[#level]
        end
        local next_level = {}
        for i = 1, #level, 2 do
            next_level[#next_level + 1] = M.digest(level[i] .. level[i + 1])
        end
        level = next_level
    end
    return level[1]
end
function M.short(value)
    return value:sub(1, 8)
end
return M
