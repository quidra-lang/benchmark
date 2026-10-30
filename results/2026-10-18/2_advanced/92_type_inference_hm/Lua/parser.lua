local lexer = require("lexer")
local P = {}
P.__index = P
P.operators = { ["||"] = { 1, true }, ["&&"] = { 2, true }, ["="] = { 3, false }, ["<>"] = { 3, false },
    ["<"] = { 3, false }, [">"] = { 3, false }, ["<="] = { 3, false }, [">="] = { 3, false },
    ["::"] = { 4, true }, ["^"] = { 4, true }, ["+"] = { 5, false }, ["-"] = { 5, false },
    ["*"] = { 6, false }, ["/"] = { 6, false }, mod = { 6, false } }
local function node(kind, position, children, value)
    return { kind = kind, position = position, children = children or {}, value = value }
end
function P.new(tokens) return setmetatable({ tokens = tokens, index = 1 }, P) end
function P:peek() return self.tokens[self.index] end
function P:fail() error({ category = "syntax", token = self:peek() }, 0) end
function P:accept(kind)
    if self:peek().kind ~= kind then return false end
    local tok = self:peek()
    self.index = self.index + 1
    return tok
end
function P:expect(kind)
    local tok = self:accept(kind)
    if not tok then self:fail() end
    return tok
end
function P:name()
    if not lexer.is_name(self:peek()) then self:fail() end
    return self:expect("identifier")
end
function P:recover()
    while self:peek().kind ~= ";;" and self:peek().kind ~= "EOF" do self.index = self.index + 1 end
    self:accept(";;")
end
function P:item()
    if self:accept("val") then
        local name = self:name()
        self:expect(":")
        local declared = self:type_expression()
        self:expect(";;")
        return { kind = "signature", value = { name, declared } }
    end
    local opening, result = self:accept("let")
    if opening then
        local group = self:group()
        if self:accept("in") then
            result = { kind = "expression", value = node("let", opening.position, { self:expression() }, group) }
        else result = { kind = "declaration", value = group } end
    else result = { kind = "expression", value = self:expression() } end
    self:expect(";;")
    return result
end
function P:group()
    local rec = self:accept("rec")
    local bindings = { self:binding() }
    while self:accept("and") do bindings[#bindings + 1] = self:binding() end
    return { bindings = bindings, rec_position = rec and rec.position or false }
end
function P:binding()
    local name, parameters = self:name(), {}
    while self:peek().kind == "identifier" do parameters[#parameters + 1] = self:expect("identifier") end
    self:expect("=")
    local expression = self:expression()
    for i = #parameters, 1, -1 do expression = node("fun", parameters[i].position, { expression }, parameters[i]) end
    return { name = name.spelling, position = name.position, expression = expression, classification = "" }
end
function P:expression()
    local opening = self:accept("let")
    if opening then
        local group = self:group()
        self:expect("in")
        return node("let", opening.position, { self:expression() }, group)
    end
    opening = self:accept("fun")
    if opening then
        local parameters = { self:expect("identifier") }
        while self:peek().kind == "identifier" do parameters[#parameters + 1] = self:expect("identifier") end
        self:expect("->")
        local expression = self:expression()
        for i = #parameters, 1, -1 do expression = node("fun", parameters[i].position, { expression }, parameters[i]) end
        expression.position = opening.position
        return expression
    end
    opening = self:accept("if")
    if opening then
        local condition = self:expression()
        self:expect("then")
        local first = self:expression()
        self:expect("else")
        return node("if", opening.position, { condition, first, self:expression() })
    end
    opening = self:accept("match")
    if opening then
        local expression = self:expression()
        self:expect("with")
        self:accept("|")
        local arms = { self:arm() }
        while self:accept("|") do arms[#arms + 1] = self:arm() end
        return node("match", opening.position, { expression }, arms)
    end
    return self:binary(1)
end
function P:arm()
    local pattern = self:pattern()
    self:expect("->")
    return { pattern, self:expression() }
end
function P:binary(minimum)
    local expression = self:unary()
    while P.operators[self:peek().kind] do
        local op = P.operators[self:peek().kind]
        if op[1] < minimum then break end
        local token = self:peek()
        self.index = self.index + 1
        expression = node("binary", expression.position,
            { expression, self:binary(op[2] and op[1] or op[1] + 1) }, token)
    end
    return expression
end
function P:starts_atom()
    local tok = self:peek()
    return tok.kind == "integer" or tok.kind == "string" or tok.kind == "true" or tok.kind == "false"
        or tok.kind == "(" or tok.kind == "[" or lexer.is_name(tok)
end
function P:unary()
    local operator = self:accept("-")
    if operator then return node("negate", operator.position, { self:unary() }, operator) end
    local expression = self:atom()
    while self:starts_atom() do expression = node("apply", expression.position, { expression, self:atom() }) end
    return expression
end
function P:atom()
    local tok = self:peek()
    if tok.kind == "integer" or tok.kind == "string" then
        self.index = self.index + 1
        return node(tok.kind, tok.position, {}, tok.value)
    elseif tok.kind == "true" or tok.kind == "false" then
        self.index = self.index + 1
        return node("boolean", tok.position, {}, tok.kind == "true")
    elseif lexer.is_name(tok) then
        self.index = self.index + 1
        return node("name", tok.position, {}, tok.spelling)
    elseif self:accept("(") then
        local first = self:expression()
        if self:accept(",") then
            local second = self:expression()
            self:expect(")")
            return node("pair", tok.position, { first, second })
        end
        self:expect(")")
        return first
    elseif self:accept("[") then
        local elements = {}
        if not self:accept("]") then
            elements[1] = self:expression()
            while self:accept(";") do elements[#elements + 1] = self:expression() end
            self:expect("]")
        end
        return node("list", tok.position, elements)
    end
    self:fail()
end
function P:pattern()
    local first = self:pattern_atom()
    if self:accept("::") then return node("cons", first.position, { first, self:pattern() }) end
    return first
end
function P:pattern_atom()
    local tok = self:peek()
    if tok.kind == "identifier" then
        self.index = self.index + 1
        return node(tok.spelling == "_" and "wildcard" or "name", tok.position, {}, tok.spelling)
    elseif self:accept("-") then
        local integer = self:expect("integer")
        return node("integer", tok.position, {}, -integer.value)
    elseif tok.kind == "integer" or tok.kind == "string" or tok.kind == "true" or tok.kind == "false" then
        return self:atom()
    elseif self:accept("(") then
        local first = self:pattern()
        if self:accept(",") then
            local second = self:pattern()
            self:expect(")")
            return node("pair", tok.position, { first, second })
        end
        self:expect(")")
        return first
    elseif self:accept("[") then
        local elements = {}
        if not self:accept("]") then
            elements[1] = self:pattern()
            while self:accept(";") do elements[#elements + 1] = self:pattern() end
            self:expect("]")
        end
        return node("list", tok.position, elements)
    end
    self:fail()
end
function P:type_expression()
    local first = self:list_type()
    if self:accept("*") then first = node("pair", first.position, { first, self:list_type() }) end
    if self:accept("->") then first = node("function", first.position, { first, self:type_expression() }) end
    return first
end
function P:list_type()
    local expression = self:type_atom()
    while self:peek().kind == "identifier" and self:peek().spelling == "list" do
        self.index = self.index + 1
        expression = node("list", expression.position, { expression })
    end
    return expression
end
function P:type_atom()
    local tok = self:peek()
    if tok.kind == "identifier" and (tok.spelling == "int" or tok.spelling == "bool" or tok.spelling == "string") then
        self.index = self.index + 1
        return node(tok.spelling, tok.position)
    elseif self:accept("type_variable") then return node("type_variable", tok.position, {}, tok.spelling)
    elseif self:accept("(") then
        local expression = self:type_expression()
        self:expect(")")
        return expression
    end
    self:fail()
end
return P
