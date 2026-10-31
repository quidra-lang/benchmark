local scoring = require("scoring")
local substitution = {}

local function mod(value)
    return value % 26
end

local function inverse(value)
    for candidate = 1, 25 do
        if value * candidate % 26 == 1 then
            return candidate
        end
    end
    error("non-invertible affine key")
end

function substitution.apply(text, cipher, key, encrypt)
    local a, b = 1, 0
    if cipher == "caesar" then
        b = tonumber(key)
    elseif cipher == "affine" then
        local left, right = key:match("^(%d+),(%d+)$")
        a, b = tonumber(left), tonumber(right)
    end
    local inverse_a = cipher == "affine" and inverse(a) or 1
    local plaintext, output, count = {}, {}, 0
    for i = 1, #text do
        local c = text:sub(i, i)
        if not scoring.is_letter(c) then
            output[#output + 1] = c
        else
            local x = scoring.value(c)
            local shift = 0
            if cipher == "vigenere" then
                shift = scoring.value(key:sub(count % #key + 1, count % #key + 1))
            elseif cipher == "autokey" then
                shift = count < #key and scoring.value(key:sub(count + 1, count + 1))
                    or plaintext[count - #key + 1]
            end
            local y
            if cipher == "caesar" then
                y = mod(x + (encrypt and b or -b))
            elseif cipher == "affine" then
                y = encrypt and mod(a * x + b) or mod(inverse_a * (x - b))
            else
                y = mod(x + (encrypt and shift or -shift))
            end
            plaintext[#plaintext + 1] = encrypt and x or y
            output[#output + 1] = string.char((c:match("[a-z]") and 97 or 65) + y)
            count = count + 1
        end
    end
    return table.concat(output)
end

return substitution
