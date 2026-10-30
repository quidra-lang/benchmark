local fold = require('protocol').fold
local masks = {}

function masks.matches(mask, value)
    mask, value = fold(mask), fold(value)
    local pattern, position, star, restart = 1, 1, nil, 1
    while position <= #value do
        local character = mask:sub(pattern, pattern)
        if character == '*' then
            star, pattern, restart = pattern, pattern + 1, position
        elseif pattern <= #mask and (character == '?' or character == value:sub(position, position)) then
            pattern, position = pattern + 1, position + 1
        elseif star then
            restart = restart + 1
            position, pattern = restart, star + 1
        else
            return false
        end
    end
    while mask:sub(pattern, pattern) == '*' do pattern = pattern + 1 end
    return pattern > #mask
end

function masks.normalize(argument)
    local bang, at = argument:find('!', 1, true), argument:find('@', 1, true)
    if bang and at then return argument end
    if at then return '*!' .. argument end
    if bang then return argument .. '@*' end
    if argument:find('.', 1, true) then return '*!*@' .. argument end
    return argument .. '!*@*'
end

return masks
