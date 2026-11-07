local bitio = require("bitio")
local M = {}
function M.tokenize(data, offset_bits, length_bits)
    local window, lookahead, position, tokens, prefixes = 1 << offset_bits, (1 << length_bits) + 2, 1, {}, {}
    while position <= #data do
        local distance, longest = 0, 0
        local limit = math.min(lookahead, #data - position + 1)
        if limit >= 3 then
            local key = data:sub(position, position + 2)
            local candidates = prefixes[key] or {}
            for index = #candidates, 1, -1 do
                local start = candidates[index]
                local candidate_distance = position - start
                if candidate_distance > window then
                    break
                end
                local length = 3
                while length < limit and data:byte(position + length) == data:byte(position + length - candidate_distance) do
                    length = length + 1
                end
                if length > longest then
                    distance, longest = candidate_distance, length
                end
                if longest == limit then
                    break
                end
            end
        end
        local consumed = 1
        if longest >= 3 then
            tokens[#tokens + 1] = {distance = distance, length = longest}
            consumed = longest
        else
            tokens[#tokens + 1] = {literal = data:byte(position)}
        end
        for start = position, math.min(position + consumed - 1, #data - 2) do
            local key = data:sub(start, start + 2)
            prefixes[key] = prefixes[key] or {}
            local candidates = prefixes[key]
            candidates[#candidates + 1] = start
        end
        position = position + consumed
    end
    return tokens
end
function M.copy_match(output, distance, length, original)
    if distance > #output then
        bitio.fail("bad_offset", #output)
    end
    if #output + length > original then
        bitio.fail("overrun", #output)
    end
    for index = 1, length do
        output[#output + 1] = output[#output - distance + 1]
    end
end
return M
