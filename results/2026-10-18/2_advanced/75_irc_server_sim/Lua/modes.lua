local digits = require('protocol').digits
local modes = {}

function modes.channel_items(mode, arguments)
    local items, sign, position = {}, '+', 1
    for character in mode:gmatch('.') do
        if character == '+' or character == '-' then
            sign = character
        else
            local argument
            if ('ovbk'):find(character, 1, true) or character == 'l' and sign == '+' then
                if arguments[position] ~= nil then argument = arguments[position]; position = position + 1 end
            end
            if character == 'k' and sign == '-' then
                argument = '*'
            elseif character == 'l' and sign == '+' then
                if not argument or not digits(argument) or #argument > 4 or tonumber(argument) < 1 then argument = nil end
            end
            items[#items + 1] = {sign = sign, character = character, argument = argument}
        end
    end
    return items
end

function modes.change_string(changes)
    local mode, arguments, previous = '', {}, nil
    for _, change in ipairs(changes) do
        if change.sign ~= previous then mode = mode .. change.sign; previous = change.sign end
        mode = mode .. change.character
        if change.argument ~= nil then arguments[#arguments + 1] = ' ' .. change.argument end
    end
    return mode .. table.concat(arguments)
end

return modes
