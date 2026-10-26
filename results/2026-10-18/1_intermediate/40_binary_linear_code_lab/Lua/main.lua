local function fail(reason)
    error({reason = reason}, 0)
end
local function yes(value)
    return value and "yes" or "no"
end
local function copy(values)
    local result = {}
    for i, value in ipairs(values) do
        result[i] = value
    end
    return result
end
local function zeros(count)
    local result = {}
    for i = 1, count do
        result[i] = 0
    end
    return result
end
local function bit(word, length, column)
    return (word >> (length - column)) & 1
end
local function bits(word, length)
    local result = {}
    for column = 1, length do
        result[column] = bit(word, length, column) == 1 and "1" or "0"
    end
    return table.concat(result)
end
local function weight(word)
    local count = 0
    while word ~= 0 do
        word = word & (word - 1)
        count = count + 1
    end
    return count
end
local function degree(word)
    local result = -1
    while word ~= 0 do
        word = word >> 1
        result = result + 1
    end
    return result
end
local function divide(dividend, divisor)
    local quotient, d = 0, degree(divisor)
    while dividend ~= 0 and degree(dividend) >= d do
        local shift = degree(dividend) - d
        quotient = quotient ~ (1 << shift)
        dividend = dividend ~ (divisor << shift)
    end
    return quotient, dividend
end
local function remainder(dividend, divisor)
    local _, result = divide(dividend, divisor)
    return result
end
local function basis(rows, length)
    local pivots, kept = zeros(length), {}
    for _, original in ipairs(rows) do
        local row = original
        for column = 1, length do
            if bit(row, length, column) ~= 0 then
                if pivots[column] ~= 0 then
                    row = row ~ pivots[column]
                else
                    pivots[column] = row
                    kept[#kept + 1] = original
                    break
                end
            end
        end
    end
    return kept
end
local function rref(original, length)
    local rows, columns = copy(original), {}
    for column = 1, length do
        local pivot = #columns + 1
        local found = pivot
        while found <= #rows and bit(rows[found], length, column) == 0 do
            found = found + 1
        end
        if found <= #rows then
            rows[pivot], rows[found] = rows[found], rows[pivot]
            for i, row in ipairs(rows) do
                if i ~= pivot and bit(row, length, column) ~= 0 then
                    rows[i] = row ~ rows[pivot]
                end
            end
            columns[#columns + 1] = column
        end
    end
    local reduced = {}
    for i = 1, #columns do
        reduced[i] = rows[i]
    end
    return reduced, columns
end
local function nullspace(original, length)
    local rows, columns = rref(original, length)
    local pivot, result = {}, {}
    for _, column in ipairs(columns) do
        pivot[column] = true
    end
    for column = 1, length do
        if not pivot[column] then
            local word = 1 << (length - column)
            for i, row in ipairs(rows) do
                if bit(row, length, column) ~= 0 then
                    word = word | (1 << (length - columns[i]))
                end
            end
            result[#result + 1] = word
        end
    end
    return result
end
local function span(rows)
    local words = {0}
    for _, row in ipairs(rows) do
        local count = #words
        for i = 1, count do
            words[#words + 1] = words[i] ~ row
        end
    end
    return words
end
local function distribution(words, length)
    local counts = zeros(length + 1)
    for _, word in ipairs(words) do
        local index = weight(word) + 1
        counts[index] = counts[index] + 1
    end
    return counts
end
local function weightList(counts)
    local items = {}
    for i, count in ipairs(counts) do
        if count ~= 0 then
            items[#items + 1] = (i - 1) .. ":" .. count
        end
    end
    return table.concat(items, " ")
end
local function checkDimension(n, k)
    if k < 1 or k > 12 or n - k < 1 or n - k > 12 then
        fail("bad dimension " .. n .. " " .. k)
    end
end
local function removeBit(word, length, column)
    local low = length - column
    return ((word >> (low + 1)) << low) | (word & ((1 << low) - 1))
end
local function reedMuller(order, variables)
    local length = 1 << variables
    if order == 0 then
        return {(1 << length) - 1}
    end
    local result = {}
    for _, row in ipairs(reedMuller(math.min(order, variables - 1), variables - 1)) do
        result[#result + 1] = (row << (length // 2)) | row
    end
    for _, row in ipairs(reedMuller(order - 1, variables - 1)) do
        result[#result + 1] = row
    end
    return result
end
local function gcd(a, b)
    a, b = math.abs(a), math.abs(b)
    while b ~= 0 do
        a, b = b, a % b
    end
    return a
end
local function binomial(n, k)
    if k < 0 or k > n then
        return 0
    end
    local result = 1
    for i = 1, k do
        result = result * (n - i + 1) // i
    end
    return result
end
local function volume(n, radius)
    local result = 0
    for i = 0, radius do
        result = result + binomial(n, i)
    end
    return result
end
local function krawtchouk(n, j, x)
    local result = 0
    for y = 0, j do
        result = result + (y % 2 == 0 and 1 or -1) * binomial(x, y) * binomial(n - x, j - y)
    end
    return result
end

local Code = {}
Code.__index = Code
function Code.new(n, g, h, polynomial)
    checkDimension(n, #g)
    local self =
        setmetatable(
        {
            n = n,
            k = #g,
            g = g,
            h = h or nullspace(g, n),
            polynomial = polynomial,
            words = {},
            messages = {}
        },
        Code
    )
    for message = 0, (1 << self.k) - 1 do
        local word = self:encode(message)
        self.words[#self.words + 1] = word
        self.messages[word] = message
    end
    table.sort(self.words)
    return self
end
function Code:encoder()
    return self.polynomial and "polynomial" or "matrix"
end
function Code:encode(message)
    if self.polynomial then
        local shifted = message << (self.n - self.k)
        return shifted | remainder(shifted, self.polynomial)
    end
    local result = 0
    for row, word in ipairs(self.g) do
        if bit(message, self.k, row) ~= 0 then
            result = result ~ word
        end
    end
    return result
end
function Code:syndrome(word)
    local result = 0
    for _, row in ipairs(self.h) do
        result = (result << 1) | (weight(word & row) % 2)
    end
    return result
end
function Code:leaders()
    if self.cachedLeaders then
        return self.cachedLeaders
    end
    local result = zeros(1 << (self.n - self.k))
    for i = 2, #result do
        result[i] = -1
    end
    local remaining, count = #result - 1, 1
    while remaining > 0 do
        local word = (1 << count) - 1
        while word < (1 << self.n) do
            local index = self:syndrome(word) + 1
            if result[index] == -1 then
                result[index] = word
                remaining = remaining - 1
                if remaining == 0 then
                    break
                end
            end
            local lowest = word & -word
            local nextWord = word + lowest
            word = nextWord | (((nextWord ~ word) >> 2) // lowest)
        end
        count = count + 1
    end
    self.cachedLeaders = result
    return result
end
function Code:decode(received)
    local errorWord = self:leaders()[self:syndrome(received) + 1]
    local word = received ~ errorWord
    return {error = errorWord, word = word, message = self.messages[word]}
end
function Code:decodedText(result)
    return "codeword " ..
        bits(result.word, self.n) ..
            " message " ..
                bits(result.message, self.k) ..
                    " error " .. bits(result.error, self.n) .. " weight " .. weight(result.error)
end

local function format(fixed, repeated, maximum, defining)
    return {fixed = fixed, repeated = repeated, maximum = maximum, defining = defining}
end
local Name, Existing, Number, Bits, Erasure = "name", "code", "number", "bits", "erasure"
local formats = {
    GEN = format({Name}, Bits, 24, true),
    PCHECK = format({Name}, Bits, 24, true),
    HAMMING = format({Name, Number}, nil, nil, true),
    SIMPLEX = format({Name, Number}, nil, nil, true),
    REPETITION = format({Name, Number}, nil, nil, true),
    PARITY = format({Name, Number}, nil, nil, true),
    RM = format({Name, Number, Number}, nil, nil, true),
    CYCLIC = format({Name, Number, Bits}, nil, nil, true),
    DUAL = format({Name, Existing}, nil, nil, true),
    EXTEND = format({Name, Existing}, nil, nil, true),
    PUNCTURE = format({Name, Existing, Number}, nil, nil, true),
    SHORTEN = format({Name, Existing, Number}, nil, nil, true),
    AUGMENT = format({Name, Existing}, nil, nil, true),
    EXPURGATE = format({Name, Existing}, nil, nil, true),
    PERMUTE = format({Name, Existing}, Number, 24, true),
    DIRECTSUM = format({Name, Existing, Existing}, nil, nil, true),
    UUV = format({Name, Existing, Existing}, nil, nil, true),
    PRODUCT = format({Name, Existing, Existing}, nil, nil, true),
    LIST = format({}),
    DELETE = format({Existing}),
    SHOW = format({Existing}),
    INFO = format({Existing}),
    SYSTEMATIC = format({Existing}),
    WEIGHTS = format({Existing}),
    COVERING = format({Existing}),
    BURST = format({Existing}),
    TRELLIS = format({Existing}),
    STDARRAY = format({Existing}),
    EQUAL = format({Existing, Existing}),
    ENCODE = format({Existing, Bits}),
    SYNDROME = format({Existing, Bits}),
    DECODE = format({Existing, Bits}),
    BOUNDED = format({Existing, Number, Bits}),
    COSET = format({Existing, Bits}),
    ERASURE = format({Existing, Erasure}),
    INTERLEAVE = format({Existing, Number, Number}, Bits, 8),
    CRC = format({Bits, Bits}),
    CRCCHECK = format({Bits, Bits}),
    FACTOR = format({Number}),
    MACWILLIAMS = format({Number}, Number, 25),
    BOUNDS = format({Number, Number})
}
local function valid(word, kind)
    if kind == Name or kind == Existing then
        return #word <= 8 and word:match("^[A-Za-z][A-Za-z0-9]*$") ~= nil
    end
    if kind == Number then
        return #word <= 4 and word:match("^[0-9]+$") ~= nil and
            (#word == 1 or word:sub(1, 1) ~= "0")
    end
    return #word <= 30 and word:match(kind == Bits and "^[01]+$" or "^[01?]+$") ~= nil
end
local codes = {}
local function parse(line)
    local words = {}
    for word in line:gmatch("[^ ]+") do
        words[#words + 1] = word
    end
    local verb = table.remove(words, 1)
    local form = formats[verb]
    if not form then
        fail("unknown command " .. verb)
    end
    local extra = #words - #form.fixed
    if form.repeated then
        if extra < 1 or extra > form.maximum then
            fail("bad arguments")
        end
    elseif extra ~= 0 then
        fail("bad arguments")
    end
    for i, word in ipairs(words) do
        if not valid(word, form.fixed[i] or form.repeated) then
            fail("bad arguments")
        end
    end
    for i, kind in ipairs(form.fixed) do
        if kind == Existing and not codes[words[i]] then
            fail("no code " .. words[i])
        end
    end
    return verb, words, form
end
local function define(verb, args)
    local name, n, g, h, polynomial = args[1], 0, {}, nil, nil
    if verb == "GEN" or verb == "PCHECK" then
        n = #args[2]
        for i = 2, #args do
            if #args[i] ~= n then
                fail("bad length")
            end
            g[#g + 1] = tonumber(args[i], 2)
        end
        g = basis(g, n)
        if verb == "PCHECK" then
            h = g
            g = nullspace(h, n)
        end
    elseif verb == "HAMMING" or verb == "SIMPLEX" then
        local r = tonumber(args[2], 10)
        if r < 2 or r > 4 then
            fail("bad parameter")
        end
        n = (1 << r) - 1
        g = zeros(r)
        for column = 1, n do
            for row = 1, r do
                g[row] = (g[row] << 1) | bit(column, r, row)
            end
        end
        if verb == "HAMMING" then
            h = g
            g = nullspace(h, n)
        end
    elseif verb == "REPETITION" or verb == "PARITY" then
        n = tonumber(args[2], 10)
        if n < 2 or n > 24 then
            fail("bad parameter")
        end
        if verb == "REPETITION" then
            g = {(1 << n) - 1}
        else
            for row = 1, n - 1 do
                g[row] = (1 << (n - row)) | 1
            end
        end
    elseif verb == "RM" then
        local order, variables = tonumber(args[2], 10), tonumber(args[3], 10)
        if variables < 1 or variables > 4 or order > variables then
            fail("bad parameter")
        end
        n = 1 << variables
        g = reedMuller(order, variables)
    elseif verb == "CYCLIC" then
        local text = args[3]
        n = tonumber(args[2], 10)
        if n < 2 or n > 24 or text:sub(1, 1) == "0" or #text < 2 or #text > n then
            fail("bad parameter")
        end
        polynomial = tonumber(text, 2)
        if remainder((1 << n) | 1, polynomial) ~= 0 then
            fail("not a divisor")
        end
        local d = #text - 1
        local k = n - d
        for row = 1, k do
            g[row] = polynomial << (k - row)
        end
        h = zeros(d)
        for column = 1, n do
            local rem = remainder(1 << (n - column), polynomial)
            for row = 1, d do
                h[row] = (h[row] << 1) | bit(rem, d, row)
            end
        end
    elseif verb == "DIRECTSUM" or verb == "UUV" or verb == "PRODUCT" then
        local a, b = codes[args[2]], codes[args[3]]
        if verb == "UUV" and a.n ~= b.n then
            fail("bad length")
        end
        n = verb == "PRODUCT" and a.n * b.n or a.n + b.n
        checkDimension(n, verb == "PRODUCT" and a.k * b.k or a.k + b.k)
        if verb == "PRODUCT" then
            for _, x in ipairs(a.g) do
                for _, y in ipairs(b.g) do
                    local word = 0
                    for column = 1, a.n do
                        word = (word << b.n) | (bit(x, a.n, column) ~= 0 and y or 0)
                    end
                    g[#g + 1] = word
                end
            end
        else
            for _, row in ipairs(a.g) do
                g[#g + 1] = (row << b.n) | (verb == "UUV" and row or 0)
            end
            for _, row in ipairs(b.g) do
                g[#g + 1] = row
            end
        end
    else
        local source = codes[args[2]]
        n = source.n
        if verb == "DUAL" then
            g, h = source.h, source.g
        elseif verb == "EXTEND" then
            n = n + 1
            for i, row in ipairs(source.g) do
                g[i] = (row << 1) | (weight(row) % 2)
            end
        elseif verb == "PUNCTURE" or verb == "SHORTEN" then
            local column = tonumber(args[3], 10)
            if column < 1 or column > n then
                fail("bad position")
            end
            local rows = copy(source.g)
            if verb == "SHORTEN" then
                for pivot, z in ipairs(rows) do
                    if bit(z, n, column) ~= 0 then
                        table.remove(rows, pivot)
                        for i, row in ipairs(rows) do
                            if bit(row, n, column) ~= 0 then
                                rows[i] = row ~ z
                            end
                        end
                        break
                    end
                end
            end
            for i, row in ipairs(rows) do
                g[i] = removeBit(row, n, column)
            end
            n = n - 1
            if verb == "PUNCTURE" then
                g = basis(g, n)
            end
        elseif verb == "AUGMENT" then
            g = copy(source.g)
            g[#g + 1] = (1 << n) - 1
            g = basis(g, n)
        elseif verb == "EXPURGATE" then
            g = copy(source.g)
            for pivot, z in ipairs(g) do
                if weight(z) % 2 ~= 0 then
                    table.remove(g, pivot)
                    for i, row in ipairs(g) do
                        if weight(row) % 2 ~= 0 then
                            g[i] = row ~ z
                        end
                    end
                    break
                end
            end
        elseif verb == "PERMUTE" then
            if #args - 2 ~= n then
                fail("bad permutation")
            end
            local seen, permutation = {}, {}
            for i = 3, #args do
                local column = tonumber(args[i], 10)
                if column < 1 or column > n or seen[column] then
                    fail("bad permutation")
                end
                seen[column] = true
                permutation[#permutation + 1] = column
            end
            for i, row in ipairs(source.g) do
                local word = 0
                for _, column in ipairs(permutation) do
                    word = (word << 1) | bit(row, n, column)
                end
                g[i] = word
            end
        end
    end
    local code = Code.new(n, g, h, polynomial)
    local action = codes[name] and "redefined" or "defined"
    codes[name] = code
    return {action .. " " .. name .. " n " .. n .. " k " .. code.k}
end
local function systematic(name, code)
    local n, k, rows, permutation = code.n, code.k, copy(code.g), {}
    for i = 1, n do
        permutation[i] = i
    end
    for pivot = 1, k do
        local column, found = pivot, pivot
        while true do
            found = pivot
            while found <= k and bit(rows[found], n, column) == 0 do
                found = found + 1
            end
            if found <= k then
                break
            end
            column = column + 1
        end
        if column ~= pivot then
            local mask = (1 << (n - pivot)) | (1 << (n - column))
            for i, row in ipairs(rows) do
                if bit(row, n, pivot) ~= bit(row, n, column) then
                    rows[i] = row ~ mask
                end
            end
            permutation[pivot], permutation[column] = permutation[column], permutation[pivot]
        end
        rows[pivot], rows[found] = rows[found], rows[pivot]
        for i, row in ipairs(rows) do
            if i ~= pivot and bit(row, n, pivot) ~= 0 then
                rows[i] = row ~ rows[pivot]
            end
        end
    end
    local output = {"systematic " .. name .. " perm " .. table.concat(permutation, " ")}
    for _, row in ipairs(rows) do
        output[#output + 1] = "G " .. bits(row, n)
    end
    for column = k + 1, n do
        local word = 0
        for _, row in ipairs(rows) do
            word = (word << 1) | bit(row, n, column)
        end
        word = (word << (n - k)) | (1 << (n - column))
        output[#output + 1] = "H " .. bits(word, n)
    end
    return output
end
local function burst(name, code)
    local detect = code.n
    for _, word in ipairs(code.words) do
        if word ~= 0 then
            detect = math.min(detect, degree(word) - degree(word & -word))
        end
    end
    local seen = {[0] = true}
    for length = 1, code.n do
        for start = 0, code.n - length do
            local limit = length == 1 and 1 or (1 << (length - 2))
            for middle = 0, limit - 1 do
                local pattern = length == 1 and 1 or ((1 << (length - 1)) | (middle << 1) | 1)
                local syndrome = code:syndrome(pattern << (code.n - start - length))
                if seen[syndrome] then
                    return {"burst " .. name .. " detect " .. detect .. " correct " .. (length - 1)}
                end
                seen[syndrome] = true
            end
        end
    end
    error("A nonzero codeword has zero syndrome")
end
local function interleave(name, code, args)
    local start, length, depth = tonumber(args[2], 10), tonumber(args[3], 10), #args - 3
    for i = 4, #args do
        if #args[i] ~= code.k then
            fail("bad length")
        end
    end
    if start < 1 or length < 1 or start + length - 1 > depth * code.n then
        fail("bad burst")
    end
    local sentWords, receivedWords, sent, received = {}, zeros(depth), {}, {}
    for i = 1, depth do
        sentWords[i] = code:encode(tonumber(args[i + 3], 2))
    end
    for column = 1, code.n do
        for row = 1, depth do
            local position = (column - 1) * depth + row
            local original = bit(sentWords[row], code.n, column)
            local changed =
                original ~ ((position >= start and position < start + length) and 1 or 0)
            sent[position], received[position] = original, changed
            receivedWords[row] = (receivedWords[row] << 1) | changed
        end
    end
    local output = {
        "interleave " .. name .. " depth " .. depth .. " burst " .. start .. " " .. length,
        "sent " .. table.concat(sent),
        "recv " .. table.concat(received)
    }
    local correct = 0
    for row, receivedWord in ipairs(receivedWords) do
        local decoded = code:decode(receivedWord)
        local message = bits(decoded.message, code.k)
        local ok = message == args[row + 3]
        if ok then
            correct = correct + 1
        end
        output[#output + 1] =
            "row " ..
            row ..
                " errors " ..
                    weight(receivedWord ~ sentWords[row]) ..
                        " corrected " ..
                            weight(decoded.error) ..
                                " message " .. message .. " " .. (ok and "ok" or "wrong")
    end
    output[#output + 1] = "result ok " .. correct .. " wrong " .. (depth - correct)
    return output
end
local function independent(verb, args)
    if verb == "CRC" or verb == "CRCCHECK" then
        local generator, text = args[1], args[2]
        if generator:sub(1, 1) == "0" or #generator < 2 or #generator > 17 then
            fail("bad parameter")
        end
        local d = #generator - 1
        if verb == "CRC" and #text + d > 30 then
            fail("bad length")
        end
        local word = tonumber(text, 2)
        local rem = remainder(verb == "CRC" and (word << d) or word, tonumber(generator, 2))
        local suffix = bits(rem, d)
        if verb == "CRC" then
            return {"crc remainder " .. suffix .. " frame " .. text .. suffix}
        end
        return {"crccheck " .. (rem == 0 and "ok" or "error") .. " remainder " .. suffix}
    end
    local n = tonumber(args[1], 10)
    if verb == "BOUNDS" then
        local distance = tonumber(args[2], 10)
        if distance < 1 or distance > n or n > 24 then
            fail("bad parameter")
        end
        local v = volume(n, (distance - 1) // 2)
        local hamming, griesmer, sum = 0, 0, 0
        for k = 0, n do
            if (1 << k) * v <= (1 << n) then
                hamming = k
            end
        end
        for k = 1, n do
            local denominator = 1 << (k - 1)
            sum = sum + (distance + denominator - 1) // denominator
            if sum <= n then
                griesmer = k
            end
        end
        return {
            "bounds n " ..
                n ..
                    " d " ..
                        distance ..
                            " singleton " ..
                                (n - distance + 1) ..
                                    " hamming " .. hamming .. " griesmer " .. griesmer
        }
    end
    if n < 1 or n > 24 then
        fail("bad parameter")
    end
    if verb == "FACTOR" then
        local remaining, candidate, divisors, factors = (1 << n) | 1, 2, 1, {}
        while 2 * degree(candidate) <= degree(remaining) do
            local exponent = 0
            while true do
                local quotient, rem = divide(remaining, candidate)
                if rem ~= 0 then
                    break
                end
                remaining = quotient
                exponent = exponent + 1
            end
            if exponent > 0 then
                factors[#factors + 1] = bits(candidate, degree(candidate) + 1) .. "^" .. exponent
                divisors = divisors * (exponent + 1)
            end
            candidate = candidate + 1
        end
        if remaining > 1 then
            factors[#factors + 1] = bits(remaining, degree(remaining) + 1) .. "^1"
            divisors = divisors * 2
        end
        return {"factor " .. n .. " " .. table.concat(factors, " ") .. " divisors " .. divisors}
    end
    if #args ~= n + 2 then
        fail("bad length")
    end
    if tonumber(args[2], 10) ~= 1 then
        fail("bad parameter")
    end
    local counts, size = {}, 0
    for i = 2, #args do
        counts[#counts + 1] = tonumber(args[i], 10)
        size = size + counts[#counts]
    end
    local feasible, transformed = (size & (size - 1)) == 0, {}
    for j = 0, n do
        local numerator = 0
        for x = 0, n do
            numerator = numerator + counts[x + 1] * krawtchouk(n, j, x)
        end
        local divisor = gcd(numerator, size)
        local p, q = numerator // divisor, size // divisor
        transformed[#transformed + 1] = q == 1 and tostring(p) or (p .. "/" .. q)
        if q ~= 1 or p < 0 then
            feasible = false
        end
    end
    return {
        "macwilliams n " .. n .. " size " .. size,
        "dual " .. table.concat(transformed, " "),
        "feasible " .. yes(feasible)
    }
end
local function process(line)
    local verb, args, form = parse(line)
    if form.defining then
        return define(verb, args)
    end
    if
        verb == "CRC" or verb == "CRCCHECK" or verb == "FACTOR" or verb == "MACWILLIAMS" or
            verb == "BOUNDS"
     then
        return independent(verb, args)
    end
    if verb == "LIST" then
        local names = {}
        for name in pairs(codes) do
            names[#names + 1] = name
        end
        table.sort(names)
        local output = {"codes " .. #names}
        for _, name in ipairs(names) do
            local code = codes[name]
            output[#output + 1] =
                name .. " n " .. code.n .. " k " .. code.k .. " encoder " .. code:encoder()
        end
        return output
    end
    local name = args[1]
    if verb == "DELETE" then
        codes[name] = nil
        return {"deleted " .. name}
    end
    local code = codes[name]
    local n, k = code.n, code.k
    if verb == "SHOW" then
        local output = {
            "code " .. name .. " n " .. n .. " k " .. k .. " encoder " .. code:encoder()
        }
        if code.polynomial then
            local quotient = divide((1 << n) | 1, code.polynomial)
            output[#output + 1] =
                "poly g " .. bits(code.polynomial, n - k + 1) .. " h " .. bits(quotient, k + 1)
        end
        for _, row in ipairs(code.g) do
            output[#output + 1] = "G " .. bits(row, n)
        end
        for _, row in ipairs(code.h) do
            output[#output + 1] = "H " .. bits(row, n)
        end
        return output
    elseif verb == "INFO" then
        local distance, cyclic = n, true
        for _, word in ipairs(code.words) do
            if word ~= 0 then
                distance = math.min(distance, weight(word))
            end
        end
        for _, row in ipairs(code.g) do
            local rotated = ((row << 1) & ((1 << n) - 1)) | (row >> (n - 1))
            if code.messages[rotated] == nil then
                cyclic = false
            end
        end
        local t, divisor = (distance - 1) // 2, gcd(n, k)
        local generator = cyclic and bits(code.words[2], degree(code.words[2]) + 1) or "no"
        return {
            "info " ..
                name ..
                    " n " ..
                        n ..
                            " k " ..
                                k ..
                                    " rate " ..
                                        (k // divisor) ..
                                            "/" ..
                                                (n // divisor) ..
                                                    " d " ..
                                                        distance ..
                                                            " t " ..
                                                                t ..
                                                                    " perfect " ..
                                                                        yes(
                                                                            volume(n, t) ==
                                                                                (1 << (n - k))
                                                                        ) ..
                                                                            " mds " ..
                                                                                yes(
                                                                                    distance ==
                                                                                        n - k + 1
                                                                                ) ..
                                                                                    " cyclic " ..
                                                                                        generator
        }
    elseif verb == "SYSTEMATIC" then
        return systematic(name, code)
    elseif verb == "WEIGHTS" then
        local a, b, orthogonal, equal =
            distribution(code.words, n),
            distribution(span(code.h), n),
            true,
            true
        for _, x in ipairs(code.g) do
            for _, y in ipairs(code.g) do
                if weight(x & y) % 2 ~= 0 then
                    orthogonal = false
                end
            end
        end
        for i = 1, n + 1 do
            if a[i] ~= b[i] then
                equal = false
            end
        end
        return {
            "weights " .. name .. " " .. weightList(a),
            "dual " .. name .. " " .. weightList(b),
            "duality " ..
                name ..
                    " self-orthogonal " ..
                        yes(orthogonal) ..
                            " self-dual " ..
                                yes(orthogonal and n == 2 * k) ..
                                    " formally-self-dual " .. yes(equal)
        }
    elseif verb == "COVERING" then
        local counts, radius, items = distribution(code:leaders(), n), n, {}
        while counts[radius + 1] == 0 do
            radius = radius - 1
        end
        for i = 0, radius do
            items[#items + 1] = i .. ":" .. counts[i + 1]
        end
        return {
            "covering " .. name .. " radius " .. radius .. " leaders " .. table.concat(items, " ")
        }
    elseif verb == "BURST" then
        return burst(name, code)
    elseif verb == "TRELLIS" then
        local profile, maximum = {}, 0
        for cut = 0, n do
            local right, prefix, suffix = n - cut, {}, {}
            for i, row in ipairs(code.g) do
                prefix[i] = row >> right
                suffix[i] = row & ((1 << right) - 1)
            end
            local value = #basis(prefix, cut) + #basis(suffix, right) - k
            profile[#profile + 1] = value
            maximum = math.max(maximum, value)
        end
        return {
            "trellis " .. name .. " profile " .. table.concat(profile, " ") .. " max " .. maximum
        }
    elseif verb == "STDARRAY" then
        if n - k > 6 or k > 4 then
            fail("too large")
        end
        local leaders, syndromes = code:leaders(), {}
        for i = 1, #leaders do
            syndromes[i] = i
        end
        table.sort(
            syndromes,
            function(a, b)
                local wa, wb = weight(leaders[a]), weight(leaders[b])
                if wa ~= wb then
                    return wa < wb
                end
                return leaders[a] < leaders[b]
            end
        )
        local output = {"stdarray " .. name .. " rows " .. #leaders .. " columns " .. #code.words}
        for _, index in ipairs(syndromes) do
            local row = {}
            for _, word in ipairs(code.words) do
                row[#row + 1] = bits(word ~ leaders[index], n)
            end
            output[#output + 1] = bits(index - 1, n - k) .. ": " .. table.concat(row, " ")
        end
        return output
    elseif verb == "EQUAL" then
        local other = codes[args[2]]
        if n ~= other.n then
            return {"equal " .. name .. " " .. args[2] .. " no lengths " .. n .. " " .. other.n}
        end
        local rows = copy(code.g)
        for _, row in ipairs(other.g) do
            rows[#rows + 1] = row
        end
        local common = k + other.k - #basis(rows, n)
        return {
            "equal " ..
                name ..
                    " " ..
                        args[2] ..
                            " " ..
                                yes(k == common and other.k == common) .. " intersection " .. common
        }
    elseif verb == "ENCODE" then
        if #args[2] ~= k then
            fail("bad length")
        end
        return {
            "encode " ..
                name ..
                    " message " ..
                        args[2] .. " codeword " .. bits(code:encode(tonumber(args[2], 2)), n)
        }
    elseif verb == "SYNDROME" or verb == "DECODE" or verb == "BOUNDED" or verb == "COSET" then
        local text = args[verb == "BOUNDED" and 3 or 2]
        if #text ~= n then
            fail("bad length")
        end
        local word = tonumber(text, 2)
        local syndrome = code:syndrome(word)
        if verb == "SYNDROME" then
            return {
                "syndrome " ..
                    name .. " " .. bits(syndrome, n - k) .. " codeword " .. yes(syndrome == 0)
            }
        end
        local decoded = code:decode(word)
        if verb == "COSET" then
            local coset = {}
            for i, value in ipairs(code.words) do
                coset[i] = value ~ word
            end
            return {
                "coset " ..
                    name ..
                        " syndrome " ..
                            bits(syndrome, n - k) ..
                                " leader " ..
                                    bits(decoded.error, n) ..
                                        " weights " .. weightList(distribution(coset, n))
            }
        end
        if verb == "BOUNDED" and weight(decoded.error) > tonumber(args[2], 10) then
            return {"bounded " .. name .. " fail weight " .. weight(decoded.error)}
        end
        return {verb:lower() .. " " .. name .. " " .. code:decodedText(decoded)}
    elseif verb == "ERASURE" then
        local text = args[2]
        if #text ~= n then
            fail("bad length")
        end
        local mask, known, erased = 0, 0, 0
        for i = 1, n do
            local digit = text:sub(i, i)
            mask = (mask << 1) | (digit ~= "?" and 1 or 0)
            known = (known << 1) | (digit == "1" and 1 or 0)
            if digit == "?" then
                erased = erased + 1
            end
        end
        local candidates = {}
        for _, word in ipairs(code.words) do
            if (word & mask) == known then
                candidates[#candidates + 1] = word
            end
        end
        local output = "erasure " .. name .. " erased " .. erased .. " candidates " .. #candidates
        if #candidates == 1 then
            output =
                output ..
                " codeword " ..
                    bits(candidates[1], n) .. " message " .. bits(code.messages[candidates[1]], k)
        end
        return {output}
    elseif verb == "INTERLEAVE" then
        return interleave(name, code, args)
    end
    error("Unreachable command")
end

local count = tonumber(io.read("l"), 10)
for _ = 1, count do
    local ok, result = pcall(process, io.read("l"))
    if ok then
        for _, line in ipairs(result) do
            io.write(line, "\n")
        end
    elseif type(result) == "table" and result.reason then
        io.write("error: ", result.reason, "\n")
    else
        error(result, 0)
    end
end
