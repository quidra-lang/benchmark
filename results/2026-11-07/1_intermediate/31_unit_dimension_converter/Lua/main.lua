local function fail(message)
    error({ message = "ERROR " .. message }, 0)
end

local Fraction = {}
Fraction.__index = Fraction
local function fraction(n, d)
    d = d or 1
    if d < 0 then n, d = -n, -d end
    local a, b = math.abs(n), d
    while b ~= 0 do a, b = b, a % b end
    return setmetatable({ n = n // a, d = d // a }, Fraction)
end
local ONE = fraction(1)
function Fraction.__add(a, b) return fraction(a.n * b.d + b.n * a.d, a.d * b.d) end
function Fraction.__sub(a, b) return fraction(a.n * b.d - b.n * a.d, a.d * b.d) end
function Fraction.__mul(a, b) return fraction(a.n * b.n, a.d * b.d) end
function Fraction.__div(a, b) return fraction(a.n * b.d, a.d * b.n) end
function Fraction.__unm(a) return fraction(-a.n, a.d) end
function Fraction.__eq(a, b) return a.n == b.n and a.d == b.d end
function Fraction.__lt(a, b) return a.n * b.d < b.n * a.d end
function Fraction.__le(a, b) return a.n * b.d <= b.n * a.d end
function Fraction.__tostring(a)
    return a.d == 1 and tostring(a.n) or string.format("%d/%d", a.n, a.d)
end
function Fraction:power(exponent)
    local factor = exponent < 0 and ONE / self or self
    local result = ONE
    for _ = 1, math.abs(exponent) do result = result * factor end
    return result
end
function Fraction:magnitude() return fraction(math.abs(self.n), self.d) end
function Fraction:decimal()
    local n = math.abs(self.n)
    return string.format("%s%d.%06d", self.n < 0 and "-" or "", n // self.d, (n % self.d * 1000000) // self.d)
end
local function parse_number(text)
    local sign, first, separator, second = text:match("^(%-?)([0-9]+)([./]?)([0-9]*)$")
    if not sign or (separator == "") ~= (second == "") then fail("BAD NUMBER " .. text) end
    local n, d = tonumber(first, 10), 1
    if separator == "/" then
        d = tonumber(second, 10)
        if d == 0 then fail("BAD NUMBER " .. text) end
    elseif separator == "." then
        for _ = 1, #second do d = d * 10 end
        n = n * d + tonumber(second, 10)
    end
    return fraction(sign == "-" and -n or n, d)
end

local Dimension = {}
Dimension.__index = Dimension
local BASE_NAMES = { "kg", "m", "s", "A", "K", "mol", "cd" }
local function dimension(values)
    return setmetatable(values or { 0, 0, 0, 0, 0, 0, 0 }, Dimension)
end
local DIMENSIONLESS = dimension()
function Dimension.__eq(a, b)
    for i = 1, 7 do if a[i] ~= b[i] then return false end end
    return true
end
function Dimension.__add(a, b)
    local result = {}
    for i = 1, 7 do result[i] = a[i] + b[i] end
    return dimension(result)
end
function Dimension.__sub(a, b)
    local result = {}
    for i = 1, 7 do result[i] = a[i] - b[i] end
    return dimension(result)
end
function Dimension:scale(factor)
    local result = {}
    for i = 1, 7 do result[i] = self[i] * factor end
    return dimension(result)
end
function Dimension:half()
    local result = {}
    for i = 1, 7 do result[i] = self[i] // 2 end
    return dimension(result)
end
function Dimension:is_even()
    for i = 1, 7 do if self[i] % 2 ~= 0 then return false end end
    return true
end
function Dimension.__tostring(a)
    local parts = {}
    for i, symbol in ipairs(BASE_NAMES) do
        if a[i] ~= 0 then parts[#parts + 1] = a[i] == 1 and symbol or symbol .. "^" .. a[i] end
    end
    return #parts == 0 and "1" or table.concat(parts, " ")
end
local function quantity(value, dim) return { value = value, dimension = dim } end
local function notation(value, unit)
    return string.format("%s %s (%s)", value, unit, value:decimal())
end
local function match_dimensions(a, b)
    if a ~= b then fail(string.format("DIMENSION MISMATCH %s vs %s", a, b)) end
end
local function check_exponent(text)
    local value = tonumber(text, 10)
    if value < -3 or value == 0 or value > 3 then fail("BAD EXPONENT " .. text) end
    return value
end
local FUNCTIONS = { abs = 1, sqrt = 1, min = 2, max = 2 }
local function check_name(name, variable)
    if #name > 12 or not name:match("^[A-Za-z]+$") or variable and FUNCTIONS[name] then fail("BAD NAME " .. name) end
end
local function words(text, pattern)
    local result = {}
    for word in text:gmatch(pattern or "[^ ]+") do result[#result + 1] = word end
    return result
end

local KIND_ROWS = {
    "dimensionless 0 0 0 0 0 0 0", "length 0 1 0 0 0 0 0", "mass 1 0 0 0 0 0 0",
    "time 0 0 1 0 0 0 0", "current 0 0 0 1 0 0 0", "temperature 0 0 0 0 1 0 0",
    "amount 0 0 0 0 0 1 0", "luminous_intensity 0 0 0 0 0 0 1", "area 0 2 0 0 0 0 0",
    "volume 0 3 0 0 0 0 0", "speed 0 1 -1 0 0 0 0", "acceleration 0 1 -2 0 0 0 0",
    "density 1 -3 0 0 0 0 0", "momentum 1 1 -1 0 0 0 0", "force 1 1 -2 0 0 0 0",
    "energy 1 2 -2 0 0 0 0", "power 1 2 -3 0 0 0 0", "pressure 1 -1 -2 0 0 0 0",
    "frequency 0 0 -1 0 0 0 0", "charge 0 0 1 1 0 0 0", "voltage 1 2 -3 -1 0 0 0",
    "resistance 1 2 -3 -2 0 0 0", "conductance -1 -2 3 2 0 0 0", "capacitance -1 -2 4 2 0 0 0",
    "magnetic_flux 1 2 -2 -1 0 0 0", "flux_density 1 0 -2 -1 0 0 0", "inductance 1 2 -2 -2 0 0 0",
    "illuminance 0 -2 0 0 0 0 1", "catalytic_activity 0 0 -1 0 0 1 0",
}
local KINDS, KIND_ORDER = {}, {}
for _, row in ipairs(KIND_ROWS) do
    local fields = words(row)
    local values = {}
    for i = 2, 8 do values[i - 1] = tonumber(fields[i], 10) end
    KINDS[fields[1]] = dimension(values)
    KIND_ORDER[#KIND_ORDER + 1] = fields[1]
end
local BUILTIN_ROWS = {
    "m 1 length yes", "g 1/1000 mass yes", "s 1 time yes", "A 1 current yes",
    "K 1 temperature yes", "mol 1 amount yes", "cd 1 luminous_intensity yes",
    "N 1 force yes", "J 1 energy yes", "W 1 power yes", "Pa 1 pressure yes",
    "Hz 1 frequency yes", "C 1 charge yes", "V 1 voltage yes", "ohm 1 resistance yes",
    "S 1 conductance yes", "F 1 capacitance yes", "Wb 1 magnetic_flux yes",
    "T 1 flux_density yes", "H 1 inductance yes", "lx 1 illuminance yes",
    "kat 1 catalytic_activity yes", "L 1/1000 volume yes", "t 1000 mass no",
    "min 60 time no", "h 3600 time no", "day 86400 time no", "in 127/5000 length no",
    "ft 381/1250 length no", "yd 1143/1250 length no", "mi 201168/125 length no",
    "nmi 1852 length no", "ha 10000 area no", "kn 463/900 speed no",
    "bar 100000 pressure yes", "atm 101325 pressure no", "Torr 20265/152 pressure no",
    "cal 523/125 energy yes", "Wh 3600 energy yes", "Ah 3600 charge yes",
    "dC 1 temperature no", "dF 5/9 temperature no",
}
local PREFIXES = {
    { "G", fraction(1000000000) }, { "M", fraction(1000000) }, { "k", fraction(1000) },
    { "h", fraction(100) }, { "da", fraction(10) }, { "d", fraction(1, 10) },
    { "c", fraction(1, 100) }, { "m", fraction(1, 1000) },
    { "u", fraction(1, 1000000) }, { "n", fraction(1, 1000000000) },
}
local function kind_name(dim)
    for _, name in ipairs(KIND_ORDER) do if KINDS[name] == dim then return name end end
    return "-"
end

local Parser = {}
Parser.__index = Parser
local function letter(c) return c and (c >= 65 and c <= 90 or c >= 97 and c <= 122) end
local function digit(c) return c and c >= 48 and c <= 57 end
function Parser.new(source, quantity_mode)
    local tokens, i = {}, 1
    while i <= #source do
        local start, c = i, source:byte(i)
        i = i + 1
        local kind
        if letter(c) then
            while letter(source:byte(i)) do i = i + 1 end
            kind = "name"
        elseif digit(c) then
            while digit(source:byte(i)) do i = i + 1 end
            if quantity_mode and source:sub(i, i) == "." and digit(source:byte(i + 1)) then
                i = i + 2
                while digit(source:byte(i)) do i = i + 1 end
            end
            kind = "number"
        else
            local ending = quantity_mode and c == 91 and source:find("]", i, true)
            if ending and ending > i then
                i, kind = ending + 1, "unit"
            else
                local symbols = quantity_mode and "+-*/^()," or "*/^()-"
                kind = symbols:find(string.char(c), 1, true) and "symbol" or "invalid"
            end
        end
        tokens[#tokens + 1] = { kind = kind, text = source:sub(start, i - 1), position = start }
    end
    tokens[#tokens + 1] = { kind = "end", text = "", position = #source + 1 }
    return setmetatable({ source = source, tokens = tokens, index = 1 }, Parser)
end
function Parser:current() return self.tokens[self.index] end
function Parser:advance()
    local token = self:current()
    self.index = self.index + 1
    return token
end
function Parser:take(text)
    if self:current().text ~= text then return false end
    self.index = self.index + 1
    return true
end
function Parser:syntax()
    local token = self:current()
    fail(string.format("SYNTAX %s AT %s", self.source, token.kind == "end" and "END" or token.position))
end
function Parser:expect(text) if not self:take(text) then self:syntax() end end
function Parser:finish() if self:current().kind ~= "end" then self:syntax() end end
function Parser:exponent()
    local sign = self:take("-") and "-" or ""
    local token = self:current()
    if token.kind ~= "number" or token.text:find(".", 1, true) then self:syntax() end
    return sign .. self:advance().text
end
function Parser:unit_expression()
    local terms = { { op = "*", node = self:unit_term() } }
    while self:current().text == "*" or self:current().text == "/" do
        local op = self:advance().text
        terms[#terms + 1] = { op = op, node = self:unit_term() }
    end
    return { kind = "product", terms = terms }
end
function Parser:unit_term()
    local token, atom = self:current()
    if token.kind == "name" then
        atom = { kind = "name", name = self:advance().text }
    elseif token.kind == "number" and token.text:sub(1, 1) ~= "0" then
        atom = { kind = "number", text = self:advance().text }
    elseif self:take("(") then
        atom = self:unit_expression()
        self:expect(")")
    else self:syntax() end
    if self:take("^") then return { kind = "power", atom = atom, exponent = self:exponent() } end
    return atom
end
function Parser:quantity_expression()
    local node = self:product()
    while self:current().text == "+" or self:current().text == "-" do
        local op = self:advance().text
        node = { kind = "binary", op = op, left = node, right = self:product() }
    end
    return node
end
function Parser:product()
    local node = self:unary()
    while self:current().text == "*" or self:current().text == "/" do
        local op = self:advance().text
        node = { kind = "binary", op = op, left = node, right = self:unary() }
    end
    return node
end
function Parser:unary()
    if self:take("-") then return { kind = "negative", operand = self:unary() } end
    local node = self:primary()
    if self:take("^") then return { kind = "power", base = node, exponent = self:exponent() } end
    return node
end
function Parser:primary()
    local token = self:current()
    if token.kind == "number" then
        local number, unit = self:advance().text
        if self:current().kind == "unit" then unit = self:advance().text:sub(2, -2) end
        return { kind = "literal", number = number, unit = unit }
    elseif token.kind == "unit" then
        return { kind = "literal", number = "1", unit = self:advance().text:sub(2, -2) }
    elseif token.kind == "name" then
        local name = self:advance().text
        if not self:take("(") then return { kind = "variable", name = name } end
        local arguments = { self:quantity_expression() }
        while self:take(",") do arguments[#arguments + 1] = self:quantity_expression() end
        self:expect(")")
        return { kind = "call", name = name, arguments = arguments }
    elseif self:take("(") then
        local node = self:quantity_expression()
        self:expect(")")
        return node
    end
    self:syntax()
end

local Calculator = {}
Calculator.__index = Calculator
function Calculator.new()
    local units = {}
    for _, row in ipairs(BUILTIN_ROWS) do
        local fields = words(row)
        units[#units + 1] = { symbol = fields[1], quantity = quantity(parse_number(fields[2]), KINDS[fields[3]]), prefix = fields[4] == "yes" }
    end
    return setmetatable({ units = units, variables = {} }, Calculator)
end
function Calculator:resolve(name)
    for _, unit in ipairs(self.units) do if unit.symbol == name then return unit.quantity end end
    for _, prefix in ipairs(PREFIXES) do
        for _, unit in ipairs(self.units) do
            if not unit.definition and unit.prefix and name == (prefix[1] .. unit.symbol) then
                return quantity(prefix[2] * unit.quantity.value, unit.quantity.dimension)
            end
        end
    end
end
function Calculator:simplified(dim)
    for _, unit in ipairs(self.units) do
        if unit.quantity.value == ONE and unit.quantity.dimension == dim then return unit.symbol end
    end
    return tostring(dim)
end
function Calculator:format_quantity(value) return notation(value.value, self:simplified(value.dimension)) end
function Calculator:validate_unit(node, names, seen)
    if node.kind == "name" then
        node.quantity = self:resolve(node.name)
        if not node.quantity then fail("UNKNOWN UNIT " .. node.name) end
        if not seen[node.name] then names[#names + 1], seen[node.name] = node.name, true end
    elseif node.kind == "power" then
        self:validate_unit(node.atom, names, seen)
        check_exponent(node.exponent)
    elseif node.kind == "product" then
        for _, term in ipairs(node.terms) do self:validate_unit(term.node, names, seen) end
    end
end
local function unit_value(node)
    if node.kind == "name" then return node.quantity end
    if node.kind == "number" then return quantity(fraction(tonumber(node.text, 10)), DIMENSIONLESS) end
    if node.kind == "power" then
        local atom, exponent = unit_value(node.atom), tonumber(node.exponent, 10)
        return quantity(atom.value:power(exponent), atom.dimension:scale(exponent))
    end
    local value, dim = ONE, DIMENSIONLESS
    for _, term in ipairs(node.terms) do
        local next_value = unit_value(term.node)
        if term.op == "*" then value, dim = value * next_value.value, dim + next_value.dimension
        else value, dim = value / next_value.value, dim - next_value.dimension end
    end
    return quantity(value, dim)
end
function Calculator:parse_unit(text)
    local parser = Parser.new(text, false)
    local tree = parser:unit_expression()
    parser:finish()
    local names = {}
    self:validate_unit(tree, names, {})
    return { tree = tree, names = names, quantity = unit_value(tree) }
end
local function reduce(node)
    if node.kind == "name" then return { coefficient = ONE, exponents = { [node.name] = 1 } } end
    if node.kind == "number" then return { coefficient = fraction(tonumber(node.text, 10)), exponents = {} } end
    if node.kind == "power" then
        local atom, exponent = reduce(node.atom), tonumber(node.exponent, 10)
        local powers = {}
        for name, value in pairs(atom.exponents) do powers[name] = value * exponent end
        return { coefficient = atom.coefficient:power(exponent), exponents = powers }
    end
    local coefficient, powers = ONE, {}
    for _, term in ipairs(node.terms) do
        local value = reduce(term.node)
        if term.op == "*" then coefficient = coefficient * value.coefficient
        else coefficient = coefficient / value.coefficient end
        for name, power in pairs(value.exponents) do
            powers[name] = (powers[name] or 0) + (term.op == "*" and power or -power)
        end
    end
    return { coefficient = coefficient, exponents = powers }
end
local function reduced_text(parsed)
    local value, parts = reduce(parsed.tree), {}
    if value.coefficient ~= ONE then parts[#parts + 1] = tostring(value.coefficient) end
    for _, name in ipairs(parsed.names) do
        local exponent = value.exponents[name]
        if exponent ~= 0 then parts[#parts + 1] = exponent == 1 and name or name .. "^" .. exponent end
    end
    return #parts == 0 and "1" or table.concat(parts, " ")
end
local function integer_root(number)
    local low, high = 0, number + 1
    while high - low > 1 do
        local middle = low + (high - low) // 2
        if middle <= number // middle then low = middle else high = middle end
    end
    return low
end
function Calculator:evaluate(node)
    if node.kind == "literal" then
        if not node.unit then return quantity(parse_number(node.number), DIMENSIONLESS) end
        local unit = self:parse_unit(node.unit).quantity
        return quantity(parse_number(node.number) * unit.value, unit.dimension)
    elseif node.kind == "variable" then
        local value = self.variables[node.name]
        if not value then fail("UNKNOWN VARIABLE " .. node.name) end
        return value
    elseif node.kind == "negative" then
        local operand = self:evaluate(node.operand)
        return quantity(-operand.value, operand.dimension)
    elseif node.kind == "power" then
        local base = self:evaluate(node.base)
        local exponent = check_exponent(node.exponent)
        if base.value.n == 0 and exponent < 0 then fail("DIVISION BY ZERO") end
        return quantity(base.value:power(exponent), base.dimension:scale(exponent))
    elseif node.kind == "binary" then
        local a = self:evaluate(node.left)
        local b = self:evaluate(node.right)
        if node.op == "+" or node.op == "-" then
            match_dimensions(a.dimension, b.dimension)
            return quantity(node.op == "+" and a.value + b.value or a.value - b.value, a.dimension)
        elseif node.op == "*" then return quantity(a.value * b.value, a.dimension + b.dimension) end
        if b.value.n == 0 then fail("DIVISION BY ZERO") end
        return quantity(a.value / b.value, a.dimension - b.dimension)
    end
    local count = FUNCTIONS[node.name]
    if not count then fail("UNKNOWN FUNCTION " .. node.name) end
    if #node.arguments ~= count then fail("BAD ARGUMENTS " .. node.name) end
    local a = self:evaluate(node.arguments[1])
    if node.name == "abs" then return quantity(a.value:magnitude(), a.dimension) end
    if node.name == "sqrt" then
        if a.value.n < 0 then fail("NEGATIVE ROOT") end
        if not a.dimension:is_even() then fail("ODD DIMENSION " .. tostring(a.dimension)) end
        local p, q = integer_root(a.value.n), integer_root(a.value.d)
        if p * p ~= a.value.n or q * q ~= a.value.d then fail("NOT EXACT") end
        return quantity(fraction(p, q), a.dimension:half())
    end
    local b = self:evaluate(node.arguments[2])
    match_dimensions(a.dimension, b.dimension)
    if node.name == "min" then return a.value <= b.value and a or b end
    return a.value >= b.value and a or b
end
function Calculator:parse_quantity(text)
    local parser = Parser.new(text, true)
    local tree = parser:quantity_expression()
    parser:finish()
    return self:evaluate(tree)
end
local function ascii_less(a, b)
    for i = 1, math.min(#a, #b) do
        if a:byte(i) ~= b:byte(i) then return a:byte(i) < b:byte(i) end
    end
    return #a < #b
end
function Calculator:matching(dim)
    local selected = {}
    for _, unit in ipairs(self.units) do
        if unit.quantity.dimension == dim then selected[#selected + 1] = unit end
    end
    table.sort(selected, function(a, b)
        if a.quantity.value ~= b.quantity.value then return a.quantity.value < b.quantity.value end
        return ascii_less(a.symbol, b.symbol)
    end)
    return selected
end

function Calculator:execute(line)
    local w = words(line)
    local command = w[1]
    if command == "DEFINE" then
        check_name(w[2], false)
        local value = parse_number(w[4])
        local unit = self:parse_unit(w[5]).quantity
        if KINDS[w[2]] or self:resolve(w[2]) then fail("NAME TAKEN " .. w[2]) end
        if value.n <= 0 then fail("NOT POSITIVE " .. w[4]) end
        local defined = quantity(value * unit.value, unit.dimension)
        self.units[#self.units + 1] = { symbol = w[2], quantity = defined, prefix = false, definition = { value = value, expression = w[5] } }
        return string.format("DEFINE %s factor=%s dim=%s kind=%s", w[2], defined.value, defined.dimension, kind_name(defined.dimension))
    elseif command == "UNDEF" then
        local index
        for i, unit in ipairs(self.units) do if unit.symbol == w[2] then index = i break end end
        if index and not self.units[index].definition then fail("BUILTIN UNIT " .. w[2]) end
        if not index then fail("NOT DEFINED " .. w[2]) end
        table.remove(self.units, index)
        return "UNDEF " .. w[2]
    elseif command == "DEFS" then
        local lines = { "DEFS count=" .. (#self.units - #BUILTIN_ROWS) }
        for _, unit in ipairs(self.units) do
            if unit.definition then
                lines[#lines + 1] = string.format("DEF %s = %s %s factor=%s dim=%s", unit.symbol, unit.definition.value,
                    unit.definition.expression, unit.quantity.value, unit.quantity.dimension)
            end
        end
        return table.concat(lines, "\n")
    elseif command == "CONVERT" or command == "INVERT" then
        local value = parse_number(w[2])
        local a = self:parse_unit(w[3]).quantity
        local b = self:parse_unit(w[5]).quantity
        if command == "CONVERT" then match_dimensions(a.dimension, b.dimension)
        else
            if a.dimension == DIMENSIONLESS or a.dimension + b.dimension ~= DIMENSIONLESS then
                fail(string.format("NOT RECIPROCAL %s vs %s", a.dimension, b.dimension))
            end
            if value.n == 0 then fail("DIVISION BY ZERO") end
        end
        local result = command == "CONVERT" and (value * a.value) / b.value or (ONE / (value * a.value)) / b.value
        return string.format("%s %s %s = %s", command, value, w[3], notation(result, w[5]))
    elseif command == "DIM" or command == "REDUCE" or command == "SIMPLIFY" then
        local parsed = self:parse_unit(w[2])
        local unit = parsed.quantity
        if command == "DIM" then return string.format("DIM %s = %s factor=%s kind=%s", w[2], unit.dimension, unit.value, kind_name(unit.dimension)) end
        if command == "REDUCE" then return "REDUCE " .. w[2] .. " = " .. reduced_text(parsed) end
        return "SIMPLIFY " .. w[2] .. " = " .. self:format_quantity(unit)
    elseif command == "ADD" or command == "SUB" or command == "MUL" or command == "DIV" or command == "COMPARE" then
        local x = parse_number(w[2])
        local a = self:parse_unit(w[3]).quantity
        local y = parse_number(w[4])
        local b = self:parse_unit(w[5]).quantity
        local target = #w == 7 and self:parse_unit(w[7]).quantity or nil
        if command == "COMPARE" then
            match_dimensions(a.dimension, b.dimension)
            local left, right = x * a.value, y * b.value
            local relation = left < right and "<" or left > right and ">" or "="
            local ratio = right.n == 0 and "undefined" or tostring(left / right)
            return string.format("COMPARE %s %s %s %s %s ratio=%s", x, w[3], relation, y, w[5], ratio)
        end
        local op = ({ ADD = "+", SUB = "-", MUL = "*", DIV = "/" })[command]
        local prefix = string.format("%s %s %s %s %s %s = ", command, x, w[3], op, y, w[5])
        if command == "ADD" or command == "SUB" then
            match_dimensions(a.dimension, b.dimension)
            if target then match_dimensions(a.dimension, target.dimension) end
            local left, right = x * a.value, y * b.value
            local sum = command == "ADD" and left + right or left - right
            return prefix .. notation(sum / (target and target.value or a.value), target and w[7] or w[3])
        end
        local dim = command == "MUL" and a.dimension + b.dimension or a.dimension - b.dimension
        if command == "DIV" and y.n == 0 then fail("DIVISION BY ZERO") end
        if target then match_dimensions(dim, target.dimension) end
        local product = command == "MUL" and x * y or x / y
        local first, second = x * a.value, y * b.value
        local coherent = command == "MUL" and first * second or first / second
        if target then return prefix .. notation(coherent / target.value, w[7]) end
        local right_unit = w[5]
        if command == "DIV" and (right_unit:find("*", 1, true) or right_unit:find("/", 1, true)) then right_unit = "(" .. right_unit .. ")" end
        return string.format("%s%s %s%s%s = %s", prefix, product, w[3], op, right_unit, notation(coherent, self:simplified(dim)))
    elseif command == "TEMP" then
        local value = parse_number(w[2])
        local scales = { C = true, F = true, K = true, R = true }
        if not scales[w[3]] then fail("UNKNOWN SCALE " .. w[3]) end
        if not scales[w[5]] then fail("UNKNOWN SCALE " .. w[5]) end
        local kelvin = value
        if w[3] == "C" then kelvin = value + fraction(5463, 20)
        elseif w[3] == "F" then kelvin = ((value + fraction(45967, 100)) * fraction(5)) / fraction(9)
        elseif w[3] == "R" then kelvin = (value * fraction(5)) / fraction(9) end
        if kelvin.n < 0 then fail("BELOW ABSOLUTE ZERO") end
        local result = kelvin
        if w[5] == "C" then result = kelvin - fraction(5463, 20)
        elseif w[5] == "F" then result = ((kelvin * fraction(9)) / fraction(5)) - fraction(45967, 100)
        elseif w[5] == "R" then result = (kelvin * fraction(9)) / fraction(5) end
        return string.format("TEMP %s %s = %s", value, w[3], notation(result, w[5]))
    elseif command == "LIST" then
        local dim = KINDS[w[2]] or self:parse_unit(w[2]).quantity.dimension
        local selected = self:matching(dim)
        local lines = { string.format("LIST %s dim=%s kind=%s count=%d", w[2], dim, kind_name(dim), #selected) }
        for _, unit in ipairs(selected) do
            lines[#lines + 1] = string.format("UNIT %s factor=%s origin=%s prefix=%s", unit.symbol, unit.quantity.value,
                unit.definition and "user" or "builtin", unit.prefix and "yes" or "no")
        end
        return table.concat(lines, "\n")
    elseif command == "TABLE" or command == "AUTO" or command == "SPLIT" then
        local value = parse_number(w[2])
        local unit = self:parse_unit(w[3]).quantity
        if command == "TABLE" then
            local selected = self:matching(unit.dimension)
            local lines = { string.format("TABLE %s %s dim=%s count=%d", value, w[3], unit.dimension, #selected) }
            for _, row in ipairs(selected) do lines[#lines + 1] = "ROW " .. notation((value * unit.value) / row.quantity.value, row.symbol) end
            return table.concat(lines, "\n")
        elseif command == "AUTO" then
            local basis
            for _, candidate in ipairs(self.units) do
                if not candidate.definition and candidate.prefix and candidate.quantity.dimension == unit.dimension then basis = candidate break end
            end
            if not basis then fail("NO PREFIXABLE UNIT " .. tostring(unit.dimension)) end
            local scaled = (value * unit.value) / basis.quantity.value
            local magnitude, exponent, ten = scaled:magnitude(), 0, fraction(10)
            if magnitude >= ONE then
                while exponent < 9 and magnitude >= ten:power(exponent + 3) do exponent = exponent + 3 end
            elseif magnitude.n ~= 0 then
                while exponent > -9 and magnitude < ten:power(exponent) do exponent = exponent - 3 end
            end
            local prefixes = { [9] = "G", [6] = "M", [3] = "k", [0] = "", [-3] = "m", [-6] = "u", [-9] = "n" }
            return string.format("AUTO %s %s = %s", value, w[3], notation(scaled / ten:power(exponent), prefixes[exponent] .. basis.symbol))
        end
        local parts, destinations = words(w[5], "[^,]+"), {}
        for _, part in ipairs(parts) do destinations[#destinations + 1] = self:parse_unit(part).quantity end
        if value.n < 0 then fail("NEGATIVE VALUE") end
        for _, destination in ipairs(destinations) do match_dimensions(unit.dimension, destination.dimension) end
        for i = 2, #destinations do
            if destinations[i - 1].value <= destinations[i].value then fail("UNIT ORDER") end
        end
        local remaining, pieces = value * unit.value, {}
        for i = 1, #parts - 1 do
            local quotient = remaining / destinations[i].value
            local whole = quotient.n // quotient.d
            remaining = remaining - fraction(whole) * destinations[i].value
            pieces[#pieces + 1] = string.format("%d %s", whole, parts[i])
        end
        pieces[#pieces + 1] = notation(remaining / destinations[#parts].value, parts[#parts])
        return string.format("SPLIT %s %s = %s", value, w[3], table.concat(pieces, " "))
    elseif command == "LET" then
        check_name(w[2], true)
        local value = self:parse_quantity(w[4])
        self.variables[w[2]] = value
        return "LET " .. w[2] .. " = " .. self:format_quantity(value)
    elseif command == "EVAL" then
        local value = self:parse_quantity(w[2])
        if #w == 4 then
            local unit = self:parse_unit(w[4]).quantity
            match_dimensions(value.dimension, unit.dimension)
            return "EVAL " .. w[2] .. " = " .. notation(value.value / unit.value, w[4])
        end
        return "EVAL " .. w[2] .. " = " .. self:format_quantity(value)
    elseif command == "VARS" then
        local names = {}
        for name in pairs(self.variables) do names[#names + 1] = name end
        table.sort(names, ascii_less)
        local lines = { "VARS count=" .. #names }
        for _, name in ipairs(names) do lines[#lines + 1] = "VAR " .. name .. " = " .. self:format_quantity(self.variables[name]) end
        return table.concat(lines, "\n")
    end
    fail("UNKNOWN COMMAND " .. command)
end

local calculator = Calculator.new()
local count = tonumber(io.read("l"), 10)
for _ = 1, count do
    local line = io.read("l"):gsub("\r$", "")
    local ok, result = pcall(calculator.execute, calculator, line)
    if ok then io.write(result, "\n")
    elseif type(result) == "table" and result.message then io.write(result.message, "\n")
    else error(result, 0) end
end
