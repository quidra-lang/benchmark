local M = {}
local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function M.strict_base64(text)
    if #text % 4 ~= 0 then return nil end
    local data = text:gsub("=+$", "")
    if #text - #data >= 3 then return nil end
    local result, buffer, bits = {}, 0, 0
    for position = 1, #data do
        local index = alphabet:find(data:sub(position, position), 1, true)
        if index == nil then return nil end
        buffer, bits = buffer * 64 + index - 1, bits + 6
        if bits >= 8 then
            bits = bits - 8
            result[#result + 1] = string.char(buffer >> bits)
            buffer = buffer & ((1 << bits) - 1)
        end
    end
    return table.concat(result)
end

function M.decode_base64_body(text)
    local compact = text:gsub("[ \t\n]", "")
    local data = M.strict_base64(compact)
    if data == nil then return nil end
    data = data:gsub("\r\n", "\n")
    for position = 1, #data do
        local byte = data:byte(position)
        if byte ~= 9 and byte ~= 10 and (byte < 32 or byte > 126) then return nil end
    end
    return data
end

function M.decode_quoted_printable(text)
    local lines, start = {}, 1
    while true do
        local ending = text:find("\n", start, true)
        if not ending then lines[#lines + 1] = text:sub(start) break end
        lines[#lines + 1], start = text:sub(start, ending - 1), ending + 1
    end
    local output, error = {}, false
    for index, line in ipairs(lines) do
        line = line:gsub("[ \t]+$", "")
        local soft = line:sub(-1) == "="
        if soft then line = line:sub(1, -2) end
        local position = 1
        while position <= #line do
            local char, decoded = line:sub(position, position), nil
            if char == "=" then
                local digits = line:sub(position + 1, position + 2)
                if #digits == 2 and digits:match("^%x%x$") then
                    local value = tonumber(digits, 16)
                    if value == 9 or value >= 32 and value <= 126 then decoded = string.char(value) end
                end
            end
            if decoded then output[#output + 1], position = decoded, position + 3
            else output[#output + 1], position = char, position + 1 error = error or char == "=" end
        end
        if not soft and index < #lines then output[#output + 1] = "\n" end
    end
    return table.concat(output), error
end

return M
