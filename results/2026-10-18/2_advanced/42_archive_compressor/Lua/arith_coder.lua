local bitio = require("bitio")
local M = {}
local function frequency_table()
    local frequencies = {}
    for symbol = 1, 257 do
        frequencies[symbol] = 1
    end
    return {frequencies = frequencies, total = 257, rescales = 0}
end
local function update(model, symbol)
    model.frequencies[symbol + 1] = model.frequencies[symbol + 1] + 32
    model.total = model.total + 32
    if model.total >= 8192 then
        model.total = 0
        for index, frequency in ipairs(model.frequencies) do
            frequency = (frequency + 1) // 2
            model.frequencies[index], model.total = frequency, model.total + frequency
        end
        model.rescales = model.rescales + 1
    end
end
function M.encode(data)
    local writer, tables = bitio.writer(), {}
    local low, high, follow, context, contexts = 0, 65535, 0, 10, 0
    local function emit(bit)
        writer:write(bit, 1)
        for index = 1, follow do
            writer:write(1 - bit, 1)
        end
        follow = 0
    end
    for position = 1, #data + 1 do
        local symbol = position <= #data and data:byte(position) or 256
        if not tables[context] then
            tables[context], contexts = frequency_table(), contexts + 1
        end
        local model, cumulative = tables[context], 0
        for index = 1, symbol do
            cumulative = cumulative + model.frequencies[index]
        end
        local frequency, span = model.frequencies[symbol + 1], high - low + 1
        high, low = low + span * (cumulative + frequency) // model.total - 1, low + span * cumulative // model.total
        while true do
            if high < 32768 then
                emit(0)
            elseif low >= 32768 then
                emit(1)
                low, high = low - 32768, high - 32768
            elseif low >= 16384 and high < 49152 then
                follow, low, high = follow + 1, low - 16384, high - 16384
            else
                break
            end
            low, high = 2 * low, 2 * high + 1
        end
        if symbol ~= 256 then
            update(model, symbol)
            context = symbol
        end
    end
    follow = follow + 1
    emit(low < 16384 and 0 or 1)
    local rescales = 0
    for _, model in pairs(tables) do
        rescales = rescales + model.rescales
    end
    return writer:finish(), {bits = writer.bit_count, contexts = contexts, rescales = rescales}
end
function M.decode(payload, original)
    local reader, tables, output = bitio.reader(payload, true), {}, {}
    local low, high, value, context = 0, 65535, reader:read(16), 10
    while true do
        tables[context] = tables[context] or frequency_table()
        local model, cumulative = tables[context], 0
        local span = high - low + 1
        local quantile = ((value - low + 1) * model.total - 1) // span
        local symbol, frequency
        for candidate = 0, 256 do
            local current = model.frequencies[candidate + 1]
            if quantile < cumulative + current then
                symbol, frequency = candidate, current
                break
            end
            cumulative = cumulative + current
        end
        high, low = low + span * (cumulative + frequency) // model.total - 1, low + span * cumulative // model.total
        while true do
            if high < 32768 then
            elseif low >= 32768 then
                low, high, value = low - 32768, high - 32768, value - 32768
            elseif low >= 16384 and high < 49152 then
                low, high, value = low - 16384, high - 16384, value - 16384
            else
                break
            end
            low, high, value = 2 * low, 2 * high + 1, 2 * value + reader:read(1)
        end
        if symbol == 256 then
            if #output < original then
                bitio.fail("early_end", #output)
            end
            return bitio.bytes(output)
        end
        if #output == original then
            bitio.fail("overrun", #output)
        end
        output[#output + 1] = symbol
        update(model, symbol)
        context = symbol
    end
end
return M
