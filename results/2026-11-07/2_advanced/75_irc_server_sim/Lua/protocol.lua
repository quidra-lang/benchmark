local protocol = {}
local replacements = {['['] = '{', [']'] = '}', ['\\'] = '|', ['^'] = '~'}

function protocol.fold(value)
    return (value:gsub('.', function(character)
        local byte = character:byte()
        return replacements[character] or (byte >= 65 and byte <= 90 and string.char(byte + 32) or character)
    end))
end

function protocol.digits(value)
    return #value > 0 and value:find('[^0-9]') == nil
end

function protocol.valid_nickname(value)
    local function initial(character)
        local byte = character:byte()
        return byte >= 65 and byte <= 90 or byte >= 97 and byte <= 122
            or ('[]\\`_^{}|'):find(character, 1, true) ~= nil
    end
    if #value == 0 or not initial(value:sub(1, 1)) then
        return false
    end
    for i = 2, #value do
        local character, byte = value:sub(i, i), value:byte(i)
        if not initial(character) and not (byte >= 48 and byte <= 57) and character ~= '-' then
            return false
        end
    end
    return true
end

function protocol.valid_channel(value, maximum)
    return #value >= 2 and #value <= maximum and value:sub(1, 1) == '#' and not value:find(':', 1, true)
end

function protocol.parse(raw)
    local position = 1
    if raw:sub(1, 1) == ':' then
        position = raw:find(' ', 1, true)
        if not position then
            return '', {}
        end
    end
    while raw:sub(position, position) == ' ' do position = position + 1 end
    local start = position
    while position <= #raw and raw:sub(position, position) ~= ' ' do position = position + 1 end
    local command, parameters = raw:sub(start, position - 1):upper(), {}
    while position <= #raw do
        while raw:sub(position, position) == ' ' do position = position + 1 end
        if position > #raw then break end
        if raw:sub(position, position) == ':' then
            parameters[#parameters + 1] = raw:sub(position + 1)
            break
        end
        if #parameters == 14 then
            parameters[#parameters + 1] = raw:sub(position)
            break
        end
        start = position
        while position <= #raw and raw:sub(position, position) ~= ' ' do position = position + 1 end
        parameters[#parameters + 1] = raw:sub(start, position - 1)
    end
    return command, parameters
end

return protocol
