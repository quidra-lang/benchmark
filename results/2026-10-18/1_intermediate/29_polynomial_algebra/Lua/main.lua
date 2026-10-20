local function fail(message)
    error({command_error = true, message = message}, 0)
end

local function gcd(a, b)
    a, b = math.abs(a), math.abs(b)
    while b ~= 0 do a, b = b, a % b end
    return a
end

local Fraction = {}
Fraction.__index = Fraction

local function fraction(n, d)
    d = d or 1
    if d < 0 then n, d = -n, -d end
    local common = gcd(n, d)
    return setmetatable({n = n // common, d = d // common}, Fraction)
end

local function as_fraction(value)
    return type(value) == "number" and fraction(value) or value
end

function Fraction.__add(a, b)
    a, b = as_fraction(a), as_fraction(b)
    return fraction(a.n * b.d + b.n * a.d, a.d * b.d)
end

function Fraction.__sub(a, b)
    a, b = as_fraction(a), as_fraction(b)
    return fraction(a.n * b.d - b.n * a.d, a.d * b.d)
end

function Fraction.__mul(a, b)
    a, b = as_fraction(a), as_fraction(b)
    return fraction(a.n * b.n, a.d * b.d)
end

function Fraction.__div(a, b)
    a, b = as_fraction(a), as_fraction(b)
    return fraction(a.n * b.d, a.d * b.n)
end

function Fraction.__unm(a) return fraction(-a.n, a.d) end
function Fraction.__eq(a, b) return a.n == b.n and a.d == b.d end
function Fraction.__lt(a, b) return a.n * b.d < b.n * a.d end
function Fraction.__le(a, b) return a.n * b.d <= b.n * a.d end
function Fraction.__tostring(a)
    return a.d == 1 and tostring(a.n) or a.n .. "/" .. a.d
end
function Fraction:absolute() return fraction(math.abs(self.n), self.d) end

local ZERO, ONE = fraction(0), fraction(1)

local function scalar_power(value, exponent)
    local result = ONE
    for _ = 1, exponent do result = result * value end
    return result
end

local function parse_fraction(text)
    local numerator, denominator = text:match("^(-?[0-9]+)/([0-9]+)$")
    if numerator == nil then return fraction(tonumber(text, 10)) end
    denominator = tonumber(denominator, 10)
    if denominator == 0 then fail("ZERO DENOMINATOR") end
    return fraction(tonumber(numerator, 10), denominator)
end

local Polynomial = {}
Polynomial.__index = Polynomial

local function polynomial(values)
    local size = #values
    while size > 0 and values[size].n == 0 do size = size - 1 end
    local result = {}
    for i = 1, size do result[i] = values[i] end
    return setmetatable(result, Polynomial)
end

local PZERO, PONE, X = polynomial({}), polynomial({ONE}), polynomial({ZERO, ONE})
local function constant(value) return polynomial({value}) end
local function linear(value, slope) return polynomial({value, slope or ONE}) end
function Polynomial:degree() return #self - 1 end
function Polynomial:leading() return self[#self] end
function Polynomial:at(i) return self[i + 1] or ZERO end
function Polynomial:is_one() return #self == 1 and self[1] == ONE end

function Polynomial.__add(a, b)
    local result = {}
    for i = 0, math.max(#a, #b) - 1 do result[i + 1] = a:at(i) + b:at(i) end
    return polynomial(result)
end

function Polynomial.__sub(a, b)
    local result = {}
    for i = 0, math.max(#a, #b) - 1 do result[i + 1] = a:at(i) - b:at(i) end
    return polynomial(result)
end

function Polynomial.__unm(a)
    local result = {}
    for i, value in ipairs(a) do result[i] = -value end
    return polynomial(result)
end

function Polynomial.__mul(a, b)
    if #a == 0 or #b == 0 then return PZERO end
    local result = {}
    for i = 1, #a + #b - 1 do result[i] = ZERO end
    for i, left in ipairs(a) do
        for j, right in ipairs(b) do result[i + j - 1] = result[i + j - 1] + left * right end
    end
    return polynomial(result)
end

function Polynomial:scale(value)
    local result = {}
    for i, coefficient in ipairs(self) do result[i] = coefficient * value end
    return polynomial(result)
end

function Polynomial:divide_scalar(value)
    local result = {}
    for i, coefficient in ipairs(self) do result[i] = coefficient / value end
    return polynomial(result)
end

function Polynomial.__pow(a, exponent)
    if exponent == 0 then return PONE end
    if #a == 0 then return PZERO end
    if #a == 1 and a[1].d == 1 and math.abs(a[1].n) == 1 then
        return exponent % 2 == 0 and PONE or a
    end
    local result = PONE
    for _ = 1, exponent do result = result * a end
    return result
end

function Polynomial:divrem(divisor)
    local quotient, remainder = {}, {}
    for i = 1, math.max(0, #self - #divisor + 1) do quotient[i] = ZERO end
    for i, value in ipairs(self) do remainder[i] = value end
    while #remainder > 0 and #remainder >= #divisor do
        local shift = #remainder - #divisor
        local factor = remainder[#remainder] / divisor:leading()
        quotient[shift + 1] = factor
        for j, value in ipairs(divisor) do remainder[shift + j] = remainder[shift + j] - factor * value end
        while #remainder > 0 and remainder[#remainder].n == 0 do table.remove(remainder) end
    end
    return polynomial(quotient), polynomial(remainder)
end

function Polynomial:quotient(divisor)
    local quotient = self:divrem(divisor)
    return quotient
end

function Polynomial:modulo(divisor)
    local _, remainder = self:divrem(divisor)
    return remainder
end

function Polynomial:monic()
    return #self == 0 and self or self:divide_scalar(self:leading())
end

function Polynomial:derivative(count)
    local result = self
    for _ = 1, count or 1 do
        if #result <= 1 then return PZERO end
        local values = {}
        for i = 1, result:degree() do values[i] = i * result:at(i) end
        result = polynomial(values)
    end
    return result
end

function Polynomial:integral()
    local result = {ZERO}
    for i, value in ipairs(self) do result[i + 1] = value / i end
    return polynomial(result)
end

function Polynomial:evaluate(point)
    local result = ZERO
    for i = #self, 1, -1 do result = result * point + self[i] end
    return result
end

function Polynomial:compose(inner)
    local result = PZERO
    for i = #self, 1, -1 do result = result * inner + constant(self[i]) end
    return result
end

local function polynomial_gcd(a, b)
    while #b > 0 do a, b = b, a:modulo(b) end
    return a:monic()
end

local function extended_gcd(a, b)
    local s0, s1, t0, t1 = PONE, PZERO, PZERO, PONE
    while #b > 0 do
        local quotient, remainder = a:divrem(b)
        a, b = b, remainder
        s0, s1 = s1, s0 - quotient * s1
        t0, t1 = t1, t0 - quotient * t1
    end
    if #a == 0 then return a, s0, t0 end
    local divisor = a:leading()
    return a:divide_scalar(divisor), s0:divide_scalar(divisor), t0:divide_scalar(divisor)
end

function Polynomial:content()
    local multiple, common = 1, 0
    for _, value in ipairs(self) do
        multiple = multiple * value.d // gcd(multiple, value.d)
        common = gcd(common, value.n)
    end
    return fraction(self:leading().n < 0 and -common or common, multiple)
end

function Polynomial:primitive() return self:divide_scalar(self:content()) end
function Polynomial:squarefree()
    return #self < 2 and self or self:quotient(polynomial_gcd(self, self:derivative()))
end

function Polynomial:format(variable)
    variable = variable or "x"
    local terms = {}
    for i = self:degree(), 0, -1 do
        local value = self:at(i)
        if value.n ~= 0 then
            local sign = #terms == 0 and (value.n < 0 and "-" or "") or (value.n < 0 and " - " or " + ")
            local magnitude = value:absolute()
            local coefficient = i > 0 and magnitude == ONE and "" or tostring(magnitude)
            local suffix = i == 0 and "" or i == 1 and variable or variable .. "^" .. i
            terms[#terms + 1] = sign .. coefficient .. suffix
        end
    end
    return #terms == 0 and "0" or table.concat(terms)
end

local function degree_limit(condition) if condition then fail("DEGREE LIMIT") end end
local function check_product(a, b) degree_limit(#a > 0 and #b > 0 and a:degree() + b:degree() > 30) end
local function check_composition(a, b) degree_limit(#a > 1 and #b > 1 and a:degree() * b:degree() > 30) end
local function nonzero(a) if #a == 0 then fail("ZERO POLYNOMIAL") end end
local function divisor(a) if #a == 0 then fail("DIVISION BY ZERO") end end

local function divisors(value)
    local result = {}
    for i = 1, value do if value % i == 0 then result[#result + 1] = i end end
    return result
end

local function rational_roots(a)
    local remaining, zero_count = a:primitive(), 0
    while remaining[1].n == 0 do
        local coefficients = {}
        for i = 2, #remaining do coefficients[i - 1] = remaining[i] end
        remaining = polynomial(coefficients)
        zero_count = zero_count + 1
    end
    local candidates = {}
    for _, n in ipairs(divisors(math.abs(remaining[1].n))) do
        for _, d in ipairs(divisors(remaining:leading().n)) do
            if gcd(n, d) == 1 then
                candidates[#candidates + 1] = fraction(-n, d)
                candidates[#candidates + 1] = fraction(n, d)
            end
        end
    end
    table.sort(candidates)
    local roots = {}
    for _, value in ipairs(candidates) do
        local factor = linear(fraction(-value.n), fraction(value.d))
        local multiplicity = 0
        while #remaining >= 2 and remaining:evaluate(value).n == 0 do
            remaining = remaining:quotient(factor)
            multiplicity = multiplicity + 1
        end
        if multiplicity > 0 then roots[#roots + 1] = {value = value, multiplicity = multiplicity} end
    end
    if zero_count > 0 then roots[#roots + 1] = {value = ZERO, multiplicity = zero_count} end
    table.sort(roots, function(left, right) return left.value < right.value end)
    return roots, remaining
end

local function factor_text(text, multiplicity)
    return " * " .. text .. (multiplicity > 1 and "^" .. multiplicity or "")
end

local function factorization(a, roots, remaining)
    local result = tostring(a:content())
    for _, root in ipairs(roots) do
        local value = root.value
        local text = value.n == 0 and "x" or "(" .. linear(fraction(-value.n), fraction(value.d)):format() .. ")"
        result = result .. factor_text(text, root.multiplicity)
    end
    if #remaining >= 2 then result = result .. " * (" .. remaining:format() .. ")" end
    return result
end

local function squarefree_factors(a)
    local result = tostring(a:content())
    if #a == 1 then return result end
    local normalized = a:monic()
    local common = polynomial_gcd(normalized, normalized:derivative())
    local remaining, multiplicity = normalized:quotient(common), 1
    while #remaining >= 2 do
        local shared = polynomial_gcd(remaining, common)
        local factor = remaining:quotient(shared)
        if #factor >= 2 then
            local text = factor:primitive():format()
            result = result .. factor_text(text == "x" and text or "(" .. text .. ")", multiplicity)
        end
        common, remaining = common:quotient(shared), shared
        multiplicity = multiplicity + 1
    end
    return result
end

local function sign(value) return value.n < 0 and -1 or value.n > 0 and 1 or 0 end

local function sign_changes(signs)
    local previous, count = 0, 0
    for _, value in ipairs(signs) do
        if value ~= 0 then
            if previous ~= 0 and value ~= previous then count = count + 1 end
            previous = value
        end
    end
    return count
end

local function endpoint(value, kind) return {value = value, kind = kind or 0} end
local function parse_endpoint(text)
    if text == "-inf" then return endpoint(ZERO, -1) end
    if text == "inf" then return endpoint(ZERO, 1) end
    return endpoint(parse_fraction(text))
end
local function endpoint_text(point)
    return point.kind == 0 and tostring(point.value) or point.kind < 0 and "-inf" or "inf"
end
local function endpoint_less(a, b)
    if a.kind ~= b.kind then return a.kind < b.kind end
    return a.kind == 0 and a.value < b.value
end

local function sturm_sequence(a)
    local first = a:squarefree()
    local second = first:derivative()
    local sequence = {first}
    while #second > 0 do
        sequence[#sequence + 1] = second
        first, second = second, -first:modulo(second)
    end
    return sequence
end

local function variations(sequence, point)
    local signs = {}
    for _, a in ipairs(sequence) do
        local value = point.kind == 0 and sign(a:evaluate(point.value)) or sign(a:leading())
        if point.kind < 0 and a:degree() % 2 == 1 then value = -value end
        signs[#signs + 1] = value
    end
    return sign_changes(signs)
end

local function root_count(sequence, low, high)
    return variations(sequence, low) - variations(sequence, high)
end

local function isolate(a, precision)
    local sequence = sturm_sequence(a)
    local first, maximum = sequence[1], ZERO
    for i = 1, #first - 1 do
        local value = (first[i] / first:leading()):absolute()
        if maximum < value then maximum = value end
    end
    local beta, width = ONE + maximum, fraction(1, 1 << precision)
    local intervals = {}
    local function examine(low, high)
        local count = root_count(sequence, endpoint(low), endpoint(high))
        if count >= 2 then
            local middle = (low + high) / 2
            examine(low, middle)
            examine(middle, high)
        elseif count == 1 then
            while width < high - low do
                local middle = (low + high) / 2
                if root_count(sequence, endpoint(low), endpoint(middle)) >= 1 then high = middle
                else low = middle end
            end
            intervals[#intervals + 1] = "(" .. tostring(low) .. ", " .. tostring(high) .. "]"
        end
    end
    examine(-beta, beta)
    return #intervals == 0 and "none" or table.concat(intervals, ", ")
end

local function resultant(a, b)
    local result = ONE
    while #b >= 2 do
        local remainder = a:modulo(b)
        if #remainder == 0 then return ZERO end
        result = result * scalar_power(b:leading(), a:degree() - remainder:degree())
        if a:degree() * b:degree() % 2 == 1 then result = -result end
        a, b = b, remainder
    end
    return result * scalar_power(b[1], a:degree())
end

local function power_sums(a, count)
    local d, normalized, sums, output = a:degree(), a:monic(), {}, {}
    for j = 1, count do
        local value = j <= d and j * normalized:at(d - j) or ZERO
        for i = 1, math.min(j - 1, d) do value = value + normalized:at(d - i) * sums[j - i] end
        sums[j] = -value
        output[j] = tostring(sums[j])
    end
    return table.concat(output, ", ")
end

local function interpolate(values)
    local xs, differences = {}, {}
    for i = 1, #values, 2 do
        xs[#xs + 1] = values[i]
        differences[#differences + 1] = values[i + 1]
    end
    for j = 2, #xs do
        for i = 1, j - 1 do
            if xs[i] == xs[j] then fail("DUPLICATE X " .. tostring(xs[j])) end
        end
    end
    for j = 1, #xs - 1 do
        for i = #xs, j + 1, -1 do
            differences[i] = (differences[i] - differences[i - 1]) / (xs[i] - xs[i - j])
        end
    end
    local result = PZERO
    for i = #xs, 1, -1 do result = result * linear(-xs[i]) + constant(differences[i]) end
    return result
end

local function special(kind, count)
    if kind ~= "chebyshev" and kind ~= "chebyshev2" and kind ~= "legendre" and kind ~= "hermite" and kind ~= "laguerre" then
        fail("UNKNOWN KIND " .. kind)
    end
    degree_limit(count > 30)
    local previous = PONE
    if count == 0 then return previous end
    local current = (kind == "chebyshev2" or kind == "hermite") and X:scale(fraction(2))
        or kind == "laguerre" and linear(ONE, -ONE) or X
    for j = 1, count - 1 do
        local factor = kind == "legendre" and X:scale(fraction(2 * j + 1))
            or kind == "laguerre" and linear(fraction(2 * j + 1), -ONE) or X:scale(fraction(2))
        local multiplier = (kind == "legendre" or kind == "laguerre") and j or kind == "hermite" and 2 * j or 1
        local next_value = factor * current - previous:scale(fraction(multiplier))
        if kind == "legendre" or kind == "laguerre" then next_value = next_value:scale(fraction(1, j + 1)) end
        previous, current = current, next_value
    end
    return current
end

local Parser = {}
Parser.__index = Parser

local function digit(byte) return byte ~= nil and byte >= 48 and byte <= 57 end
local function upper(byte) return byte ~= nil and byte >= 65 and byte <= 90 end

function Parser.new(source)
    local tokens, i = {}, 1
    while i <= #source do
        if source:sub(i, i) == " " then
            i = i + 1
        else
            local start, kind = i, "symbol"
            i = i + 1
            if digit(source:byte(start)) then
                kind = "number"
                while digit(source:byte(i)) do i = i + 1 end
            elseif upper(source:byte(start)) then
                kind = "name"
                while upper(source:byte(i)) or digit(source:byte(i)) do i = i + 1 end
            end
            tokens[#tokens + 1] = {kind = kind, text = source:sub(start, i - 1), position = start}
        end
    end
    tokens[#tokens + 1] = {kind = "end", text = "", position = #source + 1}
    return setmetatable({tokens = tokens, position = 1}, Parser)
end

function Parser:current() return self.tokens[self.position] end
function Parser:syntax_error()
    local token = self:current()
    fail("SYNTAX AT " .. (token.kind == "end" and "END" or tostring(token.position)))
end

function Parser:accept(text)
    local token = self:current()
    if token.kind ~= "symbol" or token.text ~= text then return false end
    self.position = self.position + 1
    return true
end

function Parser:expect(text) if not self:accept(text) then self:syntax_error() end end

function Parser:primary()
    local token = self:current()
    if token.kind == "number" then
        self.position = self.position + 1
        return {kind = "literal", value = constant(fraction(tonumber(token.text, 10)))}
    end
    if self:accept("x") then return {kind = "variable"} end
    if token.kind == "name" then
        self.position = self.position + 1
        local order = 0
        while self:accept("'") do order = order + 1 end
        local reference = {kind = "reference", name = token.text, order = order}
        if not self:accept("(") then return reference end
        local argument = self:expression()
        self:expect(")")
        return {kind = "call", left = reference, right = argument}
    end
    if self:accept("(") then
        local result = self:expression()
        self:expect(")")
        return result
    end
    self:syntax_error()
end

function Parser:factor()
    local result = self:primary()
    if self:accept("^") then
        if self:current().kind ~= "number" then self:syntax_error() end
        result = {kind = "power", left = result, exponent = tonumber(self:current().text, 10)}
        self.position = self.position + 1
    end
    return result
end

function Parser:term()
    local result = self:factor()
    while true do
        local operation
        if self:accept("*") then operation = "*"
        elseif self:accept("/") then operation = "/"
        elseif self:current().kind == "name" or self:current().text == "x" or self:current().text == "(" then operation = "*"
        else break end
        result = {kind = operation, left = result, right = self:factor()}
    end
    return result
end

function Parser:expression()
    local negative = self:accept("-")
    local result = self:term()
    if negative then result = {kind = "negative", left = result} end
    while true do
        local operation
        if self:accept("+") then operation = "+"
        elseif self:accept("-") then operation = "-"
        else break end
        result = {kind = operation, left = result, right = self:term()}
    end
    return result
end

function Parser:parse()
    local result = self:expression()
    if self:current().kind ~= "end" then self:syntax_error() end
    return result
end

local function lookup(storage, name)
    local value = storage[name]
    if value == nil then fail("UNKNOWN " .. name) end
    return value
end

local function ascii_less(a, b)
    for i = 1, math.min(#a, #b) do
        if a:byte(i) ~= b:byte(i) then return a:byte(i) < b:byte(i) end
    end
    return #a < #b
end

local function evaluate_tree(node, storage)
    if node.kind == "literal" then return node.value end
    if node.kind == "variable" then return X end
    if node.kind == "reference" then return lookup(storage, node.name):derivative(node.order) end
    local a = evaluate_tree(node.left, storage)
    if node.kind == "negative" then return -a end
    if node.kind == "power" then
        degree_limit(#a > 0 and a:degree() * node.exponent > 30)
        return a ^ node.exponent
    end
    local b = evaluate_tree(node.right, storage)
    if node.kind == "+" then return a + b end
    if node.kind == "-" then return a - b end
    if node.kind == "*" then check_product(a, b); return a * b end
    if node.kind == "call" then check_composition(a, b); return a:compose(b) end
    divisor(b)
    if #b >= 2 then fail("NONCONSTANT DIVISOR") end
    return a:divide_scalar(b[1])
end

local references = {
    PRINT = {2}, DELETE = {2}, DEGREE = {2}, ADD = {3, 4}, SUB = {3, 4}, MUL = {3, 4},
    POW = {3}, DIV = {4, 5}, GCD = {3, 4}, XGCD = {5, 6}, LCM = {3, 4}, INVMOD = {3, 4},
    CRT = {3, 4, 5, 6}, MODPOW = {3, 5}, DERIV = {3}, INTEG = {3}, AREA = {2}, TANGENT = {3},
    TAYLOR = {2}, COMPOSE = {3, 4}, EVAL = {2}, ROOTS = {2}, FACTOR = {2}, SQFREE = {2},
    DESCARTES = {2}, STURM = {2}, ISOLATE = {2}, RESULTANT = {2, 3}, DISCRIM = {2}, POWERSUM = {2},
}

local function execute(storage, source)
    local words = {}
    for word in source:gmatch("[^ ]+") do words[#words + 1] = word end
    local command, name = words[1], words[2]
    local output, pending, deletion = {}, {}, nil
    local function save(destination, value)
        pending[#pending + 1] = {name = destination, value = value}
        output[#output + 1] = destination .. " = " .. value:format()
    end
    if command == "DEF" then
        local tree = Parser.new(source:sub(#name + 6)):parse()
        save(name, evaluate_tree(tree, storage))
    else
        if command == "DIV" and words[2] == words[3]
            or command == "XGCD" and (words[2] == words[3] or words[2] == words[4] or words[3] == words[4]) then
            fail("SAME NAME")
        end
        local operands = {}
        for _, i in ipairs(references[command] or {}) do operands[#operands + 1] = lookup(storage, words[i]) end
        local a, b = operands[1] or PZERO, operands[2] or PZERO
        local literal_words, values, bounds = {}, {}, {}
        if command == "AREA" or command == "STURM" then literal_words = {words[3], words[4]}
        elseif command == "TANGENT" then literal_words = {words[4]}
        elseif command == "TAYLOR" then literal_words = {words[3]}
        elseif command == "EVAL" or command == "INTERP" then
            for i = 3, #words do literal_words[#literal_words + 1] = words[i] end
        end
        for i, word in ipairs(literal_words) do
            if command == "STURM" then bounds[i] = parse_endpoint(word)
            else values[i] = parse_fraction(word) end
        end
        if command == "PRINT" then
            output[1] = name .. " = " .. a:format()
        elseif command == "DELETE" then
            deletion = name
            output[1] = "deleted " .. name
        elseif command == "LIST" then
            local names = {}
            for key in pairs(storage) do names[#names + 1] = key end
            table.sort(names, ascii_less)
            for _, key in ipairs(names) do output[#output + 1] = key .. " = " .. storage[key]:format() end
            if #output == 0 then output[1] = "no polynomials" end
        elseif command == "DEGREE" then
            output[1] = "deg(" .. name .. ") = " .. (#a == 0 and "-inf" or tostring(a:degree()))
        elseif command == "ADD" then save(name, a + b)
        elseif command == "SUB" then save(name, a - b)
        elseif command == "MUL" then check_product(a, b); save(name, a * b)
        elseif command == "POW" then
            local exponent = tonumber(words[4], 10)
            degree_limit(#a > 0 and a:degree() * exponent > 30)
            save(name, a ^ exponent)
        elseif command == "DIV" then
            divisor(b)
            local quotient, remainder = a:divrem(b)
            save(name, quotient)
            save(words[3], remainder)
        elseif command == "GCD" then save(name, polynomial_gcd(a, b))
        elseif command == "XGCD" then
            local common, s, t = extended_gcd(a, b)
            save(name, common)
            save(words[3], s)
            save(words[4], t)
        elseif command == "LCM" then
            local result = PZERO
            if #a > 0 and #b > 0 then
                local common = polynomial_gcd(a, b)
                degree_limit(a:degree() + b:degree() - common:degree() > 30)
                result = (a:quotient(common) * b):monic()
            end
            save(name, result)
        elseif command == "INVMOD" then
            divisor(b)
            if #b == 1 then fail("DEGREE TOO LOW") end
            local common, inverse = extended_gcd(a, b)
            if not common:is_one() then fail("NOT COPRIME") end
            save(name, inverse:modulo(b))
        elseif command == "CRT" then
            local c, d = operands[3], operands[4]
            divisor(b)
            divisor(d)
            degree_limit(b:degree() + d:degree() > 30)
            local common, inverse = extended_gcd(b, d)
            if not common:is_one() then fail("NOT COPRIME") end
            local first, second = a:modulo(b), c:modulo(d)
            local correction = ((second - first) * inverse):modulo(d)
            save(name, first + b * correction)
        elseif command == "MODPOW" then
            divisor(b)
            degree_limit(2 * b:degree() - 2 > 30)
            local result, base = PONE:modulo(b), a:modulo(b)
            local exponent = tonumber(words[4], 10)
            while exponent > 0 do
                if exponent % 2 == 1 then result = (result * base):modulo(b) end
                exponent = exponent // 2
                if exponent > 0 then base = (base * base):modulo(b) end
            end
            save(name, result)
        elseif command == "DERIV" then save(name, a:derivative(tonumber(words[4], 10)))
        elseif command == "INTEG" then
            degree_limit(#a > 0 and a:degree() + 1 > 30)
            save(name, a:integral())
        elseif command == "AREA" then
            local antiderivative = a:integral()
            local high = antiderivative:evaluate(values[2])
            local low = antiderivative:evaluate(values[1])
            output[1] = "integral(" .. name .. ", " .. tostring(values[1]) .. ", " .. tostring(values[2]) .. ") = " .. tostring(high - low)
        elseif command == "TANGENT" then
            local point = values[1]
            local value = a:evaluate(point)
            local slope = a:derivative():evaluate(point)
            save(name, linear(value - slope * point, slope))
        elseif command == "TAYLOR" then
            local point = values[1]
            local variable = point.n == 0 and "x" or point.n > 0 and "(x - " .. tostring(point) .. ")"
                or "(x + " .. tostring(-point) .. ")"
            output[1] = "taylor(" .. name .. ", " .. tostring(point) .. ") = " .. a:compose(linear(point)):format(variable)
        elseif command == "COMPOSE" then check_composition(a, b); save(name, a:compose(b))
        elseif command == "EVAL" then
            for _, point in ipairs(values) do output[#output + 1] = name .. "(" .. tostring(point) .. ") = " .. tostring(a:evaluate(point)) end
        elseif command == "ROOTS" or command == "FACTOR" then
            nonzero(a)
            local roots, remaining = rational_roots(a)
            if command == "ROOTS" then
                local descriptions = {}
                for _, root in ipairs(roots) do descriptions[#descriptions + 1] = tostring(root.value) .. " (" .. root.multiplicity .. ")" end
                output[1] = "roots(" .. name .. ") = " .. (#descriptions == 0 and "none" or table.concat(descriptions, ", "))
            else output[1] = "factor(" .. name .. ") = " .. factorization(a, roots, remaining) end
        elseif command == "SQFREE" then
            nonzero(a)
            output[1] = "sqfree(" .. name .. ") = " .. squarefree_factors(a)
        elseif command == "DESCARTES" then
            nonzero(a)
            local positive, negative = {}, {}
            for i = a:degree(), 0, -1 do
                local value = sign(a:at(i))
                positive[#positive + 1] = value
                negative[#negative + 1] = i % 2 == 0 and value or -value
            end
            output[1] = "descartes(" .. name .. ") = positive " .. sign_changes(positive) .. ", negative " .. sign_changes(negative)
        elseif command == "STURM" then
            nonzero(a)
            if not endpoint_less(bounds[1], bounds[2]) then fail("BAD INTERVAL") end
            local sequence = sturm_sequence(a)
            output[1] = "sturm(" .. name .. ", " .. endpoint_text(bounds[1]) .. ", " .. endpoint_text(bounds[2]) .. ") = " .. root_count(sequence, bounds[1], bounds[2])
        elseif command == "ISOLATE" then
            nonzero(a)
            local precision = tonumber(words[3], 10)
            output[1] = "isolate(" .. name .. ", " .. precision .. ") = " .. isolate(a, precision)
        elseif command == "RESULTANT" then
            nonzero(a)
            nonzero(b)
            output[1] = "res(" .. name .. ", " .. words[3] .. ") = " .. tostring(resultant(a, b))
        elseif command == "DISCRIM" or command == "POWERSUM" then
            nonzero(a)
            if #a == 1 then fail("DEGREE TOO LOW") end
            if command == "DISCRIM" then
                local value = resultant(a, a:derivative()) / a:leading()
                if a:degree() * (a:degree() - 1) // 2 % 2 == 1 then value = -value end
                output[1] = "disc(" .. name .. ") = " .. tostring(value)
            else output[1] = "powersum(" .. name .. ") = " .. power_sums(a, tonumber(words[3], 10)) end
        elseif command == "INTERP" then save(name, interpolate(values))
        elseif command == "SPECIAL" then save(name, special(words[3], tonumber(words[4], 10))) end
    end
    if deletion ~= nil then storage[deletion] = nil end
    for _, item in ipairs(pending) do storage[item.name] = item.value end
    return output
end

local storage = {}
local count = tonumber(io.read("l"), 10)
for _ = 1, count do
    local ok, result = pcall(execute, storage, io.read("l"))
    if ok then
        for _, line in ipairs(result) do io.write(line, "\n") end
    elseif type(result) == "table" and result.command_error then
        io.write("ERROR ", result.message, "\n")
    else
        error(result, 0)
    end
end
