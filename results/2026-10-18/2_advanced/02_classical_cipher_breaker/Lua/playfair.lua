local playfair = {}

function playfair.square(key)
    local text = key:upper():gsub("J", "I") .. "ABCDEFGHIKLMNOPQRSTUVWXYZ"
    local used, result = {}, {}
    for i = 1, #text do
        local char = text:sub(i, i)
        if not used[char] then
            result[#result + 1] = char
            used[char] = true
        end
    end
    return table.concat(result)
end

function playfair.valid(text)
    text = text:gsub("J", "I")
    if #text % 2 ~= 0 then
        return false
    end
    for i = 1, #text, 2 do
        if text:sub(i, i) == text:sub(i + 1, i + 1) then
            return false
        end
    end
    return true
end

function playfair.prepare(text)
    local result, i = {}, 1
    text = text:gsub("J", "I")
    while i <= #text do
        local first = text:sub(i, i)
        local second = text:sub(i + 1, i + 1)
        if second ~= "" and second ~= first then
            i = i + 2
        else
            second = first == "X" and "Q" or "X"
            i = i + 1
        end
        result[#result + 1] = first .. second
    end
    return table.concat(result)
end

function playfair.apply(text, key, encrypt)
    local board = playfair.square(key)
    local input = encrypt and playfair.prepare(text) or text:gsub("J", "I")
    local delta = encrypt and 1 or 4
    local result = {}
    for i = 1, #input, 2 do
        local a = board:find(input:sub(i, i), 1, true) - 1
        local b = board:find(input:sub(i + 1, i + 1), 1, true) - 1
        local ar, ac = a // 5, a % 5
        local br, bc = b // 5, b % 5
        if ar == br then
            ac, bc = (ac + delta) % 5, (bc + delta) % 5
        elseif ac == bc then
            ar, br = (ar + delta) % 5, (br + delta) % 5
        else
            ac, bc = bc, ac
        end
        result[#result + 1] = board:sub(ar * 5 + ac + 1, ar * 5 + ac + 1)
            .. board:sub(br * 5 + bc + 1, br * 5 + bc + 1)
    end
    return table.concat(result)
end

return playfair
