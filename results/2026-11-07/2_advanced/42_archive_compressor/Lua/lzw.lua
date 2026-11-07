local bitio = require("bitio")
local M = {}
local function encoding_dictionary()
    local result = {}
    for value = 0, 255 do
        result[string.char(value)] = value
    end
    return result
end
local function decoding_dictionary()
    local result = {}
    for value = 0, 255 do
        result[value] = string.char(value)
    end
    return result
end
function M.encode(data)
    local writer, dictionary, next_code, since_clear = bitio.writer(), encoding_dictionary(), 258, 0
    local stats = {codes = 0, clears = 0, widths = {0, 0, 0, 0}, longest = 0}
    local function emit(code, length)
        local width = math.min(12, bitio.bits(258 + since_clear))
        writer:write(code, width)
        stats.codes = stats.codes + 1
        stats.widths[width - 8] = stats.widths[width - 8] + 1
        stats.longest = math.max(stats.longest, length or 0)
        if code == 256 then
            stats.clears, since_clear = stats.clears + 1, 0
        else
            since_clear = since_clear + 1
        end
    end
    emit(256)
    local sequence = ""
    for position = 1, #data do
        local byte = data:sub(position, position)
        local extended = sequence .. byte
        if dictionary[extended] ~= nil then
            sequence = extended
        else
            emit(dictionary[sequence], #sequence)
            dictionary[extended], next_code = next_code, next_code + 1
            if next_code == 4096 then
                emit(256)
                dictionary, next_code = encoding_dictionary(), 258
            end
            sequence = byte
        end
    end
    if sequence ~= "" then
        emit(dictionary[sequence], #sequence)
    end
    emit(257)
    return writer:finish(), stats
end
function M.decode(payload, original)
    local reader, dictionary, next_code, previous, since_clear = bitio.reader(payload), decoding_dictionary(), 258, nil, 0
    local output, size = {}, 0
    while true do
        local count = since_clear
        local code = reader:read(math.min(12, bitio.bits(258 + count)), size)
        if code == 256 then
            dictionary, next_code, previous, since_clear = decoding_dictionary(), 258, nil, 0
        else
            since_clear = since_clear + 1
            if code == 257 then
                if size < original then
                    bitio.fail("early_end", size)
                end
                return table.concat(output)
            end
            if count == 3838 then
                bitio.fail("bad_code", size)
            end
            local sequence
            if not previous then
                if code >= 256 then
                    bitio.fail("bad_code", size)
                end
                sequence = dictionary[code]
            elseif code < next_code then
                sequence = dictionary[code]
            elseif code == next_code then
                sequence = dictionary[previous] .. dictionary[previous]:sub(1, 1)
            else
                bitio.fail("bad_code", size)
            end
            if size + #sequence > original then
                bitio.fail("overrun", size)
            end
            output[#output + 1], size = sequence, size + #sequence
            if previous then
                dictionary[next_code], next_code = dictionary[previous] .. sequence:sub(1, 1), next_code + 1
            end
            previous = code
        end
    end
end
return M
