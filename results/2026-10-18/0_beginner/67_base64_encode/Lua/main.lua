local function encode64(source)
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local output = {}
    for first = 1, #source, 3 do
        local remaining = math.min(3, #source - first + 1)
        local value = 0
        for offset = 0, 2 do value = value * 256 + (offset < remaining and source:byte(first + offset) or 0) end
        for i, divisor in ipairs({262144, 4096, 64, 1}) do
            local index = (value // divisor) % 64 + 1
            output[#output + 1] = i <= remaining + 1 and alphabet:sub(index, index) or "="
        end
    end
    return table.concat(output)
end

for _, source in ipairs({"Man", "Hello, World!", "", "<b>bold</b>", "a+b=c?"}) do
    io.write(string.format('"%s" -> "%s"\n', source, encode64(source)))
end
