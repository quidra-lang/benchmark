local rs = {}
local exp, log, generators = {[0] = 1}, {}, {}
for exponent = 1, 254 do
    local doubled = exp[exponent - 1] * 2
    exp[exponent] = doubled >= 256 and (doubled ~ 0x11d) or doubled
end
for exponent = 0, 254 do log[exp[exponent]] = exponent end
local function multiply(a, b) if a == 0 or b == 0 then return 0 end; return exp[(log[a] + log[b]) % 255] end
local function divide(a, b) if a == 0 then return 0 end; return exp[(log[a] - log[b] + 255) % 255] end
local function copy(values) local result = {}; for index, value in pairs(values) do result[index] = value end; return result end
local function generator(degree)
    if generators[degree] then return generators[degree] end
    local coefficients = {1}
    for exponent = 0, degree - 1 do
        local product = {}; for index = 1, #coefficients + 1 do product[index] = 0 end
        for index, coefficient in ipairs(coefficients) do
            product[index] = product[index] ~ coefficient
            product[index + 1] = product[index + 1] ~ multiply(coefficient, exp[exponent])
        end
        coefficients = product
    end
    generators[degree] = coefficients; return coefficients
end
function rs.parity(data, degree)
    local polynomial, remainder = generator(degree), copy(data)
    for index = 1, degree do remainder[#data + index] = 0 end
    for index = 1, #data do
        local leading = remainder[index]
        if leading ~= 0 then
            for offset, coefficient in ipairs(polynomial) do remainder[index + offset - 1] = remainder[index + offset - 1] ~ multiply(leading, coefficient) end
        end
    end
    local result = {}; for index = #data + 1, #remainder do result[#result + 1] = remainder[index] end
    return result
end
local function syndromes(words, degree)
    local result = {}
    for exponent = 0, degree - 1 do
        local value = 0
        for _, word in ipairs(words) do value = multiply(value, exp[exponent]) ~ word end
        result[#result + 1] = value
    end
    return result
end
local function evaluate(coefficients, degree, argument)
    local value = 0
    for index = degree, 0, -1 do value = multiply(value, argument) ~ coefficients[index] end
    return value
end
local function nonzero(values) for _, value in ipairs(values) do if value ~= 0 then return true end end; return false end
function rs.correct(received, degree)
    local original = syndromes(received, degree)
    if not nonzero(original) then return original, copy(received), {} end
    local locator = {[0] = 1}; for index = 1, degree do locator[index] = 0 end
    local previous, length, shift, beta = copy(locator), 0, 1, 1
    for step = 0, degree - 1 do
        local discrepancy = original[step + 1]
        for index = 1, length do discrepancy = discrepancy ~ multiply(locator[index], original[step - index + 1]) end
        if discrepancy == 0 then shift = shift + 1
        else
            local saved, multiplier = copy(locator), divide(discrepancy, beta)
            for index = 0, degree - shift do locator[index + shift] = locator[index + shift] ~ multiply(multiplier, previous[index]) end
            if 2 * length <= step then length, previous, beta, shift = step + 1 - length, saved, discrepancy, 1
            else shift = shift + 1 end
        end
    end
    if length > degree // 2 then return original, nil, {} end
    local positions, count = {}, #received
    for index = 0, count - 1 do
        if evaluate(locator, length, exp[(255 - (count - 1 - index)) % 255]) == 0 then positions[#positions + 1] = index end
    end
    if #positions ~= length then return original, nil, {} end
    local omega, derivative = {}, {}
    for index = 0, degree - 1 do omega[index] = 0 end
    for index = 0, length - 1 do derivative[index] = 0 end
    for index = 0, degree - 1 do
        for offset = 0, math.min(length, degree - 1 - index) do omega[index + offset] = omega[index + offset] ~ multiply(original[index + 1], locator[offset]) end
    end
    for exponent = 1, length, 2 do derivative[exponent - 1] = locator[exponent] end
    local corrected = copy(received)
    for _, index in ipairs(positions) do
        local location, inverse = exp[(count - 1 - index) % 255], exp[(255 - (count - 1 - index)) % 255]
        local denominator = evaluate(derivative, length - 1, inverse)
        if denominator == 0 then return original, nil, {} end
        corrected[index + 1] = corrected[index + 1] ~ multiply(location, divide(evaluate(omega, degree - 1, inverse), denominator))
    end
    if nonzero(syndromes(corrected, degree)) then return original, nil, {} end
    local changed = {}; for _, index in ipairs(positions) do if corrected[index + 1] ~= received[index + 1] then changed[#changed + 1] = index end end
    return original, corrected, changed
end
return rs
