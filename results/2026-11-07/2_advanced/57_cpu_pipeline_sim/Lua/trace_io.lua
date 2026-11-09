local M = {}
function M.hex(text)
    if #text == 8 and text:match('^[0-9a-f]+$') then return tonumber(text, 16) end
end
function M.register(text)
    local digits = text:match('^r(%d+)$')
    if digits and (#digits == 1 or digits:sub(1, 1) ~= '0') then
        local value = tonumber(digits)
        if value <= 31 then return value end
    end
end
local function lines(path)
    local input = assert(io.open(path, 'r'))
    local result = {}
    for line in input:lines() do result[#result + 1] = line end
    input:close()
    return result
end
function M.read()
    local config = {predictors = {}, variants = {}}
    for _, line in ipairs(lines('input/config.txt')) do
        local t = {}
        for token in line:gmatch('%S+') do t[#t + 1] = token end
        local key = t[1]
        if key == 'PREDICTOR' then
            local p = {name = t[2], scheme = t[3], parameters = {}}
            for i = 4, #t do p.parameters[#p.parameters + 1] = tonumber(t[i]) end
            config.predictors[#config.predictors + 1] = p
        elseif key == 'VARIANT' then
            config.variants[#config.variants + 1] = {name = t[2], forwarding = t[3] == 'ON', stage = t[4], latency = tonumber(t[5])}
        elseif key == 'PRIMARY' then config.primary = {t[2], t[3]}
        elseif key == 'WINDOW' then config.window = {tonumber(t[2]), tonumber(t[3])}
        else config[key:lower()] = tonumber(t[2]) end
    end
    return lines('input/trace.txt'), config
end
return M
