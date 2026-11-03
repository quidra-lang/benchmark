local E = {}
local levels = { { ["||"] = true }, { ["&&"] = true }, { ["|"] = true }, { ["^"] = true }, { ["&"] = true },
    { ["=="] = true, ["!="] = true }, { ["<"] = true, [">"] = true, ["<="] = true, [">="] = true },
    { ["<<"] = true, [">>"] = true }, { ["+"] = true, ["-"] = true }, { ["*"] = true, ["/"] = true, ["%"] = true } }
local function fail(message) error({ category = "expression", message = message }, 0) end
local function integer(spelling)
    local value = spelling
    for _, suffix in ipairs({ "ll", "LL", "l", "L" }) do
        if #value > #suffix and value:sub(-#suffix) == suffix then value = value:sub(1, #value - #suffix); break end
    end
    local base, digits
    if value:match("^0[xX][0-9a-fA-F]+$") then base, digits = 16, value:sub(3)
    elseif value:match("^0[0-7]*$") then base, digits = 8, value
    elseif value:match("^[1-9][0-9]*$") then base, digits = 10, value
    else fail('invalid integer constant "' .. spelling .. '"') end
    local result = 0
    for i = 1, #digits do
        local code = digits:byte(i)
        local digit = code <= 57 and code - 48 or (code <= 70 and code - 55 or code - 87)
        result = result * base + digit
    end
    return result
end
local function character(spelling)
    local value = spelling:sub(2, -2)
    if #value == 1 and value ~= "'" and value ~= "\\" then return value:byte() end
    local escapes = { n = 10, t = 9, ["\\"] = 92, ["'"] = 39, ['"'] = 34, ["0"] = 0 }
    if #value == 2 and value:sub(1, 1) == "\\" and escapes[value:sub(2)] ~= nil then return escapes[value:sub(2)] end
    fail("invalid character constant " .. spelling)
end
local P = {}
P.__index = P
function P:peek() return self.tokens[self.position] and self.tokens[self.position].spelling or false end
function P:expression()
    local left = self:binary(1)
    if self:peek() == "?" then
        self.position = self.position + 1
        local first = self:expression()
        if self:peek() ~= ":" then fail("'?' without following ':'") end
        self.position = self.position + 1
        left = { "conditional", left, first, self:expression() }
    end
    return left
end
function P:binary(level)
    if level == 11 then return self:unary() end
    local left = self:binary(level + 1)
    while levels[level][self:peek()] do
        local operator = self:peek()
        self.position = self.position + 1
        left = { "binary", operator, left, self:binary(level + 1) }
    end
    return left
end
function P:unary()
    local spelling = self:peek()
    if spelling == "+" or spelling == "-" or spelling == "!" or spelling == "~" then
        self.position = self.position + 1
        return { "unary", spelling, self:unary() }
    end
    local token = self.tokens[self.position]
    if not token then fail("expected value at end of expression") end
    self.position = self.position + 1
    if token.kind == "number" then return { "constant", integer(token.spelling) }
    elseif token.kind == "character" then return { "constant", character(token.spelling) }
    elseif token.kind == "identifier" then return { "identifier", token.spelling }
    elseif token.spelling == "(" then
        local value = self:expression()
        if self:peek() ~= ")" then fail("missing ')' in expression") end
        self.position = self.position + 1
        return value
    end
    fail('expected value before "' .. token.spelling .. '"')
end
function E.parse(tokens, directive)
    if #tokens == 0 then fail("#" .. directive .. " with no expression") end
    local parser = setmetatable({ tokens = tokens, position = 1 }, P)
    local tree = parser:expression()
    if parser:peek() then fail('missing binary operator before "' .. parser:peek() .. '"') end
    return tree
end
local function binary(operator, a, b)
    if operator == "/" or operator == "%" then
        if b == 0 then fail("division by zero in #if") end
        local quotient = math.abs(a) // math.abs(b)
        if (a < 0) ~= (b < 0) then quotient = -quotient end
        return operator == "/" and quotient or a - b * quotient
    elseif operator == "+" then return a + b elseif operator == "-" then return a - b
    elseif operator == "*" then return a * b elseif operator == "<<" then return a * (1 << b)
    elseif operator == ">>" then return a // (1 << b) elseif operator == "&" then return a & b
    elseif operator == "|" then return a | b elseif operator == "^" then return a ~ b
    elseif operator == "==" then return a == b and 1 or 0 elseif operator == "!=" then return a ~= b and 1 or 0
    elseif operator == "<" then return a < b and 1 or 0 elseif operator == ">" then return a > b and 1 or 0
    elseif operator == "<=" then return a <= b and 1 or 0 end
    return a >= b and 1 or 0
end
function E.evaluate(tree, warning)
    local pending, values = { { "evaluate", tree } }, {}
    while #pending > 0 do
        local command = table.remove(pending)
        local operation, item = command[1], command[2]
        if operation == "evaluate" then
            local kind = item[1]
            if kind == "constant" then values[#values + 1] = item[2]
            elseif kind == "identifier" then warning('identifier "' .. item[2] .. '" evaluates to 0'); values[#values + 1] = 0
            elseif kind == "unary" then pending[#pending + 1], pending[#pending + 2] = { "unary", item[2] }, { "evaluate", item[3] }
            elseif kind == "conditional" then pending[#pending + 1], pending[#pending + 2] = { "choose", { item[3], item[4] } }, { "evaluate", item[2] }
            elseif item[2] == "&&" or item[2] == "||" then
                pending[#pending + 1], pending[#pending + 2] = { "logical", { item[2], item[4] } }, { "evaluate", item[3] }
            else
                pending[#pending + 1], pending[#pending + 2], pending[#pending + 3] = { "binary", item[2] }, { "evaluate", item[4] }, { "evaluate", item[3] }
            end
        elseif operation == "choose" then pending[#pending + 1] = { "evaluate", table.remove(values) ~= 0 and item[1] or item[2] }
        elseif operation == "logical" then
            local first = table.remove(values)
            if (item[1] == "&&" and first == 0) or (item[1] == "||" and first ~= 0) then values[#values + 1] = first ~= 0 and 1 or 0
            else pending[#pending + 1], pending[#pending + 2] = { "truth" }, { "evaluate", item[2] } end
        elseif operation == "truth" then values[#values + 1] = table.remove(values) ~= 0 and 1 or 0
        elseif operation == "unary" then
            local value = table.remove(values)
            if item == "+" then values[#values + 1] = value elseif item == "-" then values[#values + 1] = -value
            elseif item == "!" then values[#values + 1] = value == 0 and 1 or 0 else values[#values + 1] = -value - 1 end
        else
            local b, a = table.remove(values), table.remove(values)
            values[#values + 1] = binary(item, a, b)
        end
    end
    return values[1]
end
return E
