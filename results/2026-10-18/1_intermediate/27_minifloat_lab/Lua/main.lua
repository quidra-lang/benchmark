local flags = { invalid = 1, divbyzero = 2, overflow = 4, underflow = 8, inexact = 16 }
local modes = { RNE = true, RNA = true, RTZ = true, RUP = true, RDN = true }
local operations = { ADD = 2, SUB = 2, MUL = 2, DIV = 2, SQRT = 1, FMA = 3 }
local integer_types = {
    I8 = {-128, 127}, U8 = {0, 255}, I16 = {-32768, 32767},
    U16 = {0, 65535}, I32 = {-2147483648, 2147483647}, U32 = {0, 4294967295},
}

local function fail(format, ...)
    error({command_error = true, message = string.format(format, ...)}, 0)
end

local function flags_text(value)
    local names = {}
    for i, name in ipairs({"invalid", "divbyzero", "overflow", "underflow", "inexact"}) do
        if (value & (1 << (i - 1))) ~= 0 then names[#names + 1] = name end
    end
    return "flags=" .. (#names == 0 and "none" or table.concat(names, ","))
end

local function result(pattern, raised)
    return {pattern = pattern, flags = raised or 0}
end

local function scaled(n, d, exponent)
    if exponent >= 0 then return n << exponent, d end
    return n, d << -exponent
end

local function bit_length(value)
    local length = 0
    while value ~= 0 do value, length = value >> 1, length + 1 end
    return length
end

local function gcd(a, b)
    while b ~= 0 do a, b = b, a % b end
    return a
end

local function integer_sqrt(value)
    if value == 0 then return 0 end
    local root = 1 << ((bit_length(value) + 1) // 2)
    while true do
        local next_root = (root + value // root) // 2
        if next_root >= root then return root end
        root = next_root
    end
end

local function increment(mode, negative, whole, inexact, halfway)
    if not inexact then return false end
    if mode == "RNE" then return halfway > 0 or halfway == 0 and whole % 2 ~= 0 end
    if mode == "RNA" then return halfway >= 0 end
    if mode == "RUP" then return not negative end
    if mode == "RDN" then return negative end
    return false
end

local function round_units(value, exponent, mode)
    local n, d = scaled(value.n, value.d, value.exponent - exponent)
    local whole, remainder = n // d, n % d
    if increment(mode, value.negative, whole, remainder ~= 0, 2 * remainder - d) then whole = whole + 1 end
    return whole, remainder ~= 0
end

local function round_sqrt_units(value, exponent, mode)
    local n, d = scaled(value.n, value.d, value.exponent - 2 * exponent)
    local whole = integer_sqrt(n // d)
    local inexact = whole * whole * d ~= n
    local midpoint = 2 * whole + 1
    if increment(mode, false, whole, inexact, 4 * n - d * midpoint * midpoint) then whole = whole + 1 end
    return whole, inexact
end

local Exact = {}
Exact.__index = Exact

function Exact.new(n, exponent, d, negative)
    return setmetatable({n = n, exponent = exponent or 0, d = d or 1, negative = negative or false}, Exact)
end

function Exact:negated()
    return Exact.new(self.n, self.exponent, self.d, not self.negative)
end

function Exact:log2_floor()
    local t = bit_length(self.n) - bit_length(self.d) + self.exponent
    local n, d = scaled(self.n, self.d, self.exponent - t)
    return n < d and t - 1 or t
end

function Exact:fraction()
    if self.n == 0 then return "0" end
    local n, d = scaled(self.n, self.d, self.exponent)
    local factor = gcd(n, d)
    n, d = n // factor, d // factor
    return (self.negative and "-" or "") .. n .. (d == 1 and "" or "/" .. d)
end

function Exact:decimal(keep_zero_sign)
    local n, d = scaled(self.n, self.d, self.exponent)
    local text = {(self.negative and (self.n ~= 0 or keep_zero_sign) and "-" or "") .. (n // d)}
    local remainder = n % d
    if remainder ~= 0 then
        text[#text + 1] = "."
        while remainder ~= 0 do
            remainder = remainder * 10
            text[#text + 1] = string.char(48 + remainder // d)
            remainder = remainder % d
        end
    end
    return table.concat(text)
end

function Exact.product(a, b)
    return Exact.new(a.n * b.n, a.exponent + b.exponent, a.d * b.d, a.negative ~= b.negative)
end

function Exact.sum(terms, mode)
    local exponent
    for _, term in ipairs(terms) do
        if term.n ~= 0 and (exponent == nil or term.exponent < exponent) then exponent = term.exponent end
    end
    if exponent == nil then
        local negative, same = terms[1].negative, true
        for _, term in ipairs(terms) do same = same and term.negative == terms[1].negative end
        if not same then negative = mode == "RDN" end
        return Exact.new(0, 0, 1, negative)
    end
    local numerator = 0
    for _, term in ipairs(terms) do
        if term.n ~= 0 then
            local aligned = term.n << (term.exponent - exponent)
            numerator = numerator + (term.negative and -aligned or aligned)
        end
    end
    return Exact.new(math.abs(numerator), exponent, 1, numerator < 0 or numerator == 0 and mode == "RDN")
end

local function binary(value, width)
    local digits = {}
    for i = width - 1, 0, -1 do digits[#digits + 1] = ((value >> i) & 1) == 0 and "0" or "1" end
    return table.concat(digits)
end

local function relation(a, b)
    return a < b and "LT" or a > b and "GT" or "EQ"
end

local MiniFormat = {}
MiniFormat.__index = MiniFormat

function MiniFormat.new(name, e, m)
    local bias, hidden, mask = (1 << (e - 1)) - 1, 1 << m, (1 << e) - 1
    return setmetatable({name = name, e = e, m = m, width = 1 + e + m, bias = bias,
        emin = 1 - bias, emax = bias, hidden = hidden, exponent_mask = mask,
        sign_bit = 1 << (e + m), infinity = mask * hidden}, MiniFormat)
end

function MiniFormat:fields(pattern)
    local exponent = (pattern >> self.m) & self.exponent_mask
    return {negative = (pattern & self.sign_bit) ~= 0, exponent = exponent, fraction = pattern & (self.hidden - 1),
        q = (exponent == 0 and self.emin or exponent - self.bias) - self.m}
end
function MiniFormat:is_nan(pattern)
    local f = self:fields(pattern)
    return f.exponent == self.exponent_mask and f.fraction ~= 0
end
function MiniFormat:is_signaling(pattern) return self:is_nan(pattern) and self:fields(pattern).fraction < self.hidden // 2 end
function MiniFormat:is_infinity(pattern) return (pattern & (self.sign_bit - 1)) == self.infinity end
function MiniFormat:is_zero(pattern) return (pattern & (self.sign_bit - 1)) == 0 end
function MiniFormat:is_finite(pattern) return self:fields(pattern).exponent ~= self.exponent_mask end
function MiniFormat:nan() return self.infinity + self.hidden // 2 end
function MiniFormat:zero(negative) return negative and self.sign_bit or 0 end
function MiniFormat:inf(negative) return self:zero(negative) + self.infinity end
function MiniFormat:flip(pattern) return pattern ~ self.sign_bit end

function MiniFormat:exact(pattern)
    local f = self:fields(pattern)
    return Exact.new(f.exponent == 0 and f.fraction or self.hidden + f.fraction, f.q, 1, f.negative)
end
function MiniFormat:bits(pattern)
    local f = self:fields(pattern)
    return (f.negative and "1" or "0") .. "|" .. binary(f.exponent, self.e) .. "|" .. binary(f.fraction, self.m)
end
function MiniFormat:hex(pattern) return string.format("0x%0" .. ((self.width + 3) // 4) .. "X", pattern) end
function MiniFormat:value(pattern)
    if self:is_nan(pattern) then return "nan" end
    if self:is_infinity(pattern) then return self:fields(pattern).negative and "-inf" or "inf" end
    return self:exact(pattern):decimal(true)
end
function MiniFormat:pattern_text(pattern) return self:bits(pattern) .. " " .. self:hex(pattern) .. " " .. self:value(pattern) end
function MiniFormat:result_text(value) return self:pattern_text(value.pattern) .. " " .. flags_text(value.flags) end

function MiniFormat:overflow(negative, mode)
    local infinity = mode == "RNE" or mode == "RNA" or mode == "RUP" and not negative or mode == "RDN" and negative
    return result(self:zero(negative) + (infinity and self.infinity or self.infinity - 1), flags.overflow | flags.inexact)
end

function MiniFormat:round_nonzero(negative, t, mode, units_at)
    if t > self.emax then return self:overflow(negative, mode) end
    local exponent = math.max(t, self.emin) - self.m
    local n, inexact = units_at(exponent)
    if n == 2 * self.hidden then n, exponent = self.hidden, exponent + 1 end
    if exponent > self.emax - self.m then return self:overflow(negative, mode) end
    local magnitude = n >= self.hidden and (exponent + self.m + self.bias) * self.hidden + n - self.hidden or n
    local raised = inexact and flags.inexact or 0
    if inexact and t < self.emin then
        local tiny = t < self.emin - 1
        if not tiny then
            local unbounded = units_at(t - self.m)
            tiny = unbounded < 2 * self.hidden
        end
        if tiny then raised = raised | flags.underflow end
    end
    return result(self:zero(negative) + magnitude, raised)
end

function MiniFormat:round(value, mode)
    if value.n == 0 then return result(self:zero(value.negative)) end
    return self:round_nonzero(value.negative, value:log2_floor(), mode, function(q) return round_units(value, q, mode) end)
end
function MiniFormat:sqrt(value, mode)
    return self:round_nonzero(false, value:log2_floor() // 2, mode, function(q) return round_sqrt_units(value, q, mode) end)
end

local function mode_at(words, index)
    if words[index] == nil then return "RNE" end
    if not modes[words[index]] then fail("BAD MODE %s", words[index]) end
    return words[index]
end

local function real_input(word)
    if word == "nan" then return {kind = "nan", number = Exact.new(0)} end
    if word == "inf" or word == "-inf" then return {kind = "infinity", number = Exact.new(0, 0, 1, word == "-inf")} end
    local prefix = word:sub(1, 2)
    if prefix == "0b" or prefix == "0x" then fail("BAD OPERAND %s", word) end
    local negative = word:sub(1, 1) == "-"
    local body = negative and word:sub(2) or word
    local slash = body:find("/", 1, true)
    if slash then
        local n, d = tonumber(body:sub(1, slash - 1), 10), tonumber(body:sub(slash + 1), 10)
        if d == 0 then fail("BAD OPERAND %s", word) end
        return {kind = "finite", number = Exact.new(n, 0, d, negative)}
    end
    local dot = body:find(".", 1, true)
    local denominator = 1
    if dot then
        for _ = dot + 1, #body do denominator = denominator * 10 end
        body = body:gsub("%.", "")
    end
    return {kind = "finite", number = Exact.new(tonumber(body, 10), 0, denominator, negative)}
end

local function input_text(input)
    if input.kind == "nan" then return "nan" end
    if input.kind == "infinity" then return input.number.negative and "-inf" or "inf" end
    return input.number:fraction()
end

local function encoded(f, input, mode)
    if input.kind == "nan" then return result(f:nan()) end
    if input.kind == "infinity" then return result(f:inf(input.number.negative)) end
    return f:round(input.number, mode)
end

local function operand(f, word)
    local prefix = word:sub(1, 2)
    if prefix == "0b" or prefix == "0x" then
        local bits = prefix == "0b"
        if #word - 2 ~= (bits and f.width or (f.width + 3) // 4) then fail("BAD OPERAND %s", word) end
        local pattern = tonumber(word:sub(3), bits and 2 or 16)
        if pattern >= (1 << f.width) then fail("BAD OPERAND %s", word) end
        return pattern
    end
    return encoded(f, real_input(word), "RNE").pattern
end

local function calculate(f, operation, mode, inputs)
    local any_nan, signaling = false, false
    for _, pattern in ipairs(inputs) do
        any_nan = any_nan or f:is_nan(pattern)
        signaling = signaling or f:is_signaling(pattern)
    end
    if any_nan then return result(f:nan(), signaling and flags.invalid or 0) end
    local a = inputs[1]
    local negative = f:fields(a).negative
    local invalid = result(f:nan(), flags.invalid)
    if operation == "SQRT" then
        if f:is_zero(a) then return result(a) end
        if negative then return invalid end
        if f:is_infinity(a) then return result(a) end
        return f:sqrt(f:exact(a), mode)
    end
    local b = operation == "SUB" and f:flip(inputs[2]) or inputs[2]
    local sigma = negative ~= f:fields(b).negative
    if operation == "ADD" or operation == "SUB" then
        if f:is_infinity(a) and f:is_infinity(b) and sigma then return invalid end
        if f:is_infinity(a) then return result(a) end
        if f:is_infinity(b) then return result(b) end
        return f:round(Exact.sum({f:exact(a), f:exact(b)}, mode), mode)
    end
    if operation == "MUL" then
        if f:is_infinity(a) or f:is_infinity(b) then
            return (f:is_zero(a) or f:is_zero(b)) and invalid or result(f:inf(sigma))
        end
        if f:is_zero(a) or f:is_zero(b) then return result(f:zero(sigma)) end
        return f:round(Exact.product(f:exact(a), f:exact(b)), mode)
    end
    if operation == "DIV" then
        if f:is_infinity(a) then return f:is_infinity(b) and invalid or result(f:inf(sigma)) end
        if f:is_infinity(b) then return result(f:zero(sigma)) end
        if f:is_zero(b) then return f:is_zero(a) and invalid or result(f:inf(sigma), flags.divbyzero) end
        if f:is_zero(a) then return result(f:zero(sigma)) end
        local x, y = f:exact(a), f:exact(b)
        return f:round(Exact.new(x.n * y.d, x.exponent - y.exponent, x.d * y.n, sigma), mode)
    end
    local c = inputs[3]
    if f:is_infinity(a) or f:is_infinity(b) then
        if f:is_zero(a) or f:is_zero(b) or f:is_infinity(c) and f:fields(c).negative ~= sigma then return invalid end
        return result(f:inf(sigma))
    end
    if f:is_infinity(c) then return result(c) end
    return f:round(Exact.sum({Exact.product(f:exact(a), f:exact(b)), f:exact(c)}, mode), mode)
end

local function next_up(f, pattern)
    if pattern == f.infinity then return pattern end
    if f:is_zero(pattern) then return 1 end
    return pattern + (f:fields(pattern).negative and -1 or 1)
end

local function difference(f, pattern, exact)
    if not f:is_finite(pattern) then return f:value(pattern) end
    return Exact.sum({f:exact(pattern), exact:negated()}, "RNE"):fraction()
end

local Laboratory = {}
Laboratory.__index = Laboratory

function Laboratory.new()
    return setmetatable({formats = {
        HALF = MiniFormat.new("HALF", 5, 10), E5M2 = MiniFormat.new("E5M2", 5, 2), E4M3 = MiniFormat.new("E4M3", 4, 3),
    }, output = {}}, Laboratory)
end

function Laboratory:emit(format, ...)
    self.output[#self.output + 1] = string.format(format, ...)
end

function Laboratory:format(name)
    if not self.formats[name] then fail("UNKNOWN FORMAT %s", name) end
    return self.formats[name]
end

local function operands(f, words, first, last)
    local patterns = {}
    for i = first, last do patterns[#patterns + 1] = operand(f, words[i]) end
    return patterns
end

function Laboratory:summary(f, mode, patterns, value)
    local terms = {}
    for _, pattern in ipairs(patterns) do terms[#terms + 1] = f:exact(pattern) end
    local exact = Exact.sum(terms, mode)
    self:emit("RESULT %s", f:result_text(value))
    self:emit("EXACT %s", exact:decimal())
    self:emit("ROUNDED %s", f:result_text(f:round(exact, mode)))
    self:emit("DIFF %s", difference(f, value.pattern, exact))
end

function Laboratory:summation(command, f, mode, patterns)
    for _, pattern in ipairs(patterns) do if not f:is_finite(pattern) then fail("NOT FINITE") end end
    self:emit("%s %s %s count=%d", command, f.name, mode, #patterns)
    local sum, compensation, raised = patterns[1], 0, 0
    for i = 2, #patterns do
        if command == "SUM" then
            local added = calculate(f, "ADD", mode, {sum, patterns[i]})
            sum, raised = added.pattern, raised | added.flags
            self:emit("PARTIAL %d %s", i, f:result_text(added))
        else
            local y = calculate(f, "SUB", mode, {patterns[i], compensation})
            local t = calculate(f, "ADD", mode, {sum, y.pattern})
            local d = calculate(f, "SUB", mode, {t.pattern, sum})
            local c = calculate(f, "SUB", mode, {d.pattern, y.pattern})
            sum, compensation = t.pattern, c.pattern
            local step = y.flags | t.flags | d.flags | c.flags
            raised = raised | step
            self:emit("KSTEP %d sum=%s comp=%s %s", i, f:value(sum), f:value(compensation), flags_text(step))
        end
    end
    self:summary(f, mode, patterns, result(sum, raised))
end

function Laboratory:dot(f, mode, a, b)
    if #a ~= #b then fail("LENGTH MISMATCH") end
    for _, pattern in ipairs(a) do if not f:is_finite(pattern) then fail("NOT FINITE") end end
    for _, pattern in ipairs(b) do if not f:is_finite(pattern) then fail("NOT FINITE") end end
    local naive = calculate(f, "MUL", mode, {a[1], b[1]})
    local chained = naive
    for i = 2, #a do
        local product = calculate(f, "MUL", mode, {a[i], b[i]})
        local added = calculate(f, "ADD", mode, {naive.pattern, product.pattern})
        naive = result(added.pattern, naive.flags | product.flags | added.flags)
        local fused = calculate(f, "FMA", mode, {a[i], b[i], chained.pattern})
        chained = result(fused.pattern, chained.flags | fused.flags)
    end
    local terms = {}
    for i = 1, #a do terms[i] = Exact.product(f:exact(a[i]), f:exact(b[i])) end
    local exact = Exact.sum(terms, mode)
    self:emit("DOT %s %s n=%d", f.name, mode, #a)
    self:emit("NAIVE %s", f:result_text(naive))
    self:emit("CHAINED %s", f:result_text(chained))
    self:emit("EXACT %s", exact:decimal())
    self:emit("FUSED %s", f:result_text(f:round(exact, mode)))
    self:emit("DIFF naive=%s chained=%s", difference(f, naive.pattern, exact), difference(f, chained.pattern, exact))
end

function Laboratory:table(f)
    if f.width > 8 then fail("TABLE TOO LARGE") end
    local count = f.infinity
    self:emit("TABLE %s count=%d", f.name, count)
    for pattern = 0, count - 1 do
        local gap = "-"
        if pattern < count - 1 then gap = Exact.sum({f:exact(pattern + 1), f:exact(pattern):negated()}, "RNE"):decimal() end
        self:emit("ENTRY %d %s gap=%s", pattern, f:pattern_text(pattern), gap)
    end
    self:emit("MAX %s", f:pattern_text(f.infinity - 1))
    self:emit("MINNORMAL %s", f:pattern_text(f.hidden))
    self:emit("MINSUBNORMAL %s", f:pattern_text(1))
    self:emit("EPSILON %s", Exact.new(1, -f.m):decimal())
    self:emit("PATTERNS finite=%d infinite=2 nan=%d total=%d", 2 * count, 2 * (f.hidden - 1), 1 << f.width)
end

function Laboratory:execute(line)
    self.output = {}
    local words = {}
    for word in line:gmatch("%S+") do words[#words + 1] = word end
    local command = words[1]
    if command == "FORMAT" then
        local name, e, m = words[2], tonumber(words[3], 10), tonumber(words[4], 10)
        if self.formats[name] then fail("FORMAT EXISTS %s", name) end
        if e < 2 or e > 5 or m < 1 or m > 10 then fail("BAD FORMAT") end
        local f = MiniFormat.new(name, e, m)
        self.formats[name] = f
        self:emit("FORMAT %s e=%d m=%d bits=%d bias=%d emin=%d emax=%d", name, e, m, f.width, f.bias, f.emin, f.emax)
        return self.output
    end
    local f = self:format(words[2])
    if command == "ENCODE" then
        local input = real_input(words[3])
        local mode = mode_at(words, 4)
        self:emit("ENCODE %s %s %s %s", f.name, mode, input_text(input), f:result_text(encoded(f, input, mode)))
    elseif command == "CONVERT" then
        local g = self:format(words[3])
        local a = operand(f, words[4])
        local mode = mode_at(words, 5)
        local value
        if f:is_nan(a) then value = result(g:nan(), f:is_signaling(a) and flags.invalid or 0)
        elseif f:is_infinity(a) then value = result(g:inf(f:fields(a).negative))
        else value = g:round(f:exact(a), mode) end
        self:emit("CONVERT %s %s %s %s", f.name, g.name, mode, g:result_text(value))
    elseif command == "SUM" or command == "KAHAN" or command == "DOT" then
        local mode = mode_at(words, 3)
        if command == "DOT" then
            local separator = 4
            while words[separator] ~= "|" do separator = separator + 1 end
            local a = operands(f, words, 4, separator - 1)
            local b = operands(f, words, separator + 1, #words)
            self:dot(f, mode, a, b)
        else self:summation(command, f, mode, operands(f, words, 4, #words)) end
    elseif command == "TABLE" then
        self:table(f)
    elseif operations[command] then
        local count = operations[command]
        local patterns = operands(f, words, 3, 2 + count)
        local mode = mode_at(words, 3 + count)
        self:emit("%s %s %s %s", command, f.name, mode, f:result_text(calculate(f, command, mode, patterns)))
    else
        local a = operand(f, words[3])
        local fields = f:fields(a)
        if command == "DECODE" then
            local classification
            if f:is_nan(a) then classification = f:is_signaling(a) and "snan" or "qnan"
            elseif f:is_infinity(a) then classification = "infinity"
            elseif f:is_zero(a) then classification = "zero"
            else classification = fields.exponent == 0 and "subnormal" or "normal" end
            self:emit("DECODE %s %s %s %s sign=%d", f.name, f:bits(a), f:hex(a), classification, fields.negative and 1 or 0)
            local heading = string.format("FIELDS exponent=%d fraction=%d", fields.exponent, fields.fraction)
            if f:is_finite(a) then
                self:emit("%s unbiased=%d significand=%d.%s", heading, fields.q + f.m, fields.exponent == 0 and 0 or 1, binary(fields.fraction, f.m))
                self:emit("VALUE %s %s", f:exact(a):fraction(), f:value(a))
            elseif f:is_nan(a) then self:emit("%s payload=%d", heading, fields.fraction % (f.hidden // 2))
            else self:emit("%s", heading) end
        elseif command == "COMPARE" then
            local b = operand(f, words[4])
            local function key(p) return f:fields(p).negative and -(p - f.sign_bit) - 1 or p end
            local order = relation(key(a), key(b))
            local numeric = order
            if f:is_nan(a) or f:is_nan(b) then numeric = "UN"
            elseif f:is_zero(a) and f:is_zero(b) then numeric = "EQ" end
            local raised = (f:is_signaling(a) or f:is_signaling(b)) and flags.invalid or 0
            self:emit("COMPARE %s %s %s %s total=%s %s", f.name, f:hex(a), f:hex(b), numeric, order, flags_text(raised))
        elseif command == "TOINT" then
            local range = integer_types[words[4]]
            if not range then fail("BAD TYPE %s", words[4]) end
            local mode = mode_at(words, 5)
            local prefix = string.format("TOINT %s %s %s", f.name, words[4], mode)
            if not f:is_finite(a) then self:emit("%s invalid flags=invalid", prefix)
            else
                local whole, inexact = round_units(f:exact(a), 0, mode)
                local integer = fields.negative and -whole or whole
                if integer < range[1] or integer > range[2] then self:emit("%s invalid flags=invalid", prefix)
                else self:emit("%s %d %s", prefix, integer, flags_text(inexact and flags.inexact or 0)) end
            end
        else
            local value
            if f:is_nan(a) then value = result(f:nan(), f:is_signaling(a) and flags.invalid or 0)
            elseif command == "NEXTUP" then value = result(next_up(f, a))
            elseif command == "NEXTDOWN" then value = result(f:flip(next_up(f, f:flip(a))))
            else value = result(f:is_infinity(a) and f.infinity or f:round(Exact.new(1, fields.q), "RNE").pattern) end
            self:emit("%s %s %s", command, f.name, f:result_text(value))
        end
    end
    return self.output
end

local count = tonumber(io.read("*l"), 10)
local laboratory = Laboratory.new()
for _ = 1, count do
    local ok, response = pcall(function() return laboratory:execute(io.read("*l")) end)
    if ok then io.write(table.concat(response, "\n"), "\n")
    elseif type(response) == "table" and response.command_error then io.write("ERROR ", response.message, "\n")
    else error(response, 0) end
end
