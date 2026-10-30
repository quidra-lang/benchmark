local lexer = require("lexer")
local P = {}
P.__index = P
local precedence = { ["||"] = 1, ["&&"] = 2, ["=="] = 3, ["!="] = 3,
    ["<"] = 4, ["<="] = 4, [">"] = 4, [">="] = 4, ["+"] = 5, ["-"] = 5,
    ["*"] = 6, ["/"] = 6, ["%"] = 6 }
local function node(tag, first, props)
    props = props or {}
    props.tag, props.first = tag, first
    return props
end

function P:peek() return self.tokens[self.cursor] end
function P:at(symbol) return self:peek().text == symbol end
function P:fail(expected)
    local actual = self:peek()
    local found = actual.kind == "end" and "end of file" or "'" .. actual.text .. "'"
    lexer.fail(actual.line, actual.column, "expected " .. expected .. ", found " .. found)
end
function P:take(symbol)
    if not self:at(symbol) then self:fail("'" .. symbol .. "'") end
    local tok = self:peek()
    self.cursor = self.cursor + 1
    return tok
end
function P:identifier()
    if self:peek().kind ~= "identifier" then self:fail("identifier") end
    local tok = self:peek()
    self.cursor = self.cursor + 1
    return tok
end
function P:typ()
    if not lexer.types[self:peek().text] then self:fail("type") end
    local tok = self:peek()
    self.cursor = self.cursor + 1
    return tok
end

function P:item()
    local typ, name = self:typ(), self:identifier()
    typ.allowed = true
    if self:at("(") then
        local parameters = self:list("(", ")", P.parameter, false)
        return node("function", typ, { typ = typ, name = name, parameters = parameters, body = self:block() })
    end
    return self:variable(typ, name, true)
end
function P:parameter()
    local typ, name = self:typ(), self:identifier()
    local brackets = {}
    while self:at("[") do brackets[#brackets + 1] = { self:take("["), self:take("]") } end
    return node("parameter", typ, { typ = typ, name = name, brackets = brackets })
end
function P:variable(typ, name, semicolon)
    local dimensions = {}
    while self:at("[") do
        local left = self:take("[")
        local expr = not self:at("]") and self:expression() or false
        dimensions[#dimensions + 1] = { left, expr, self:take("]") }
    end
    local equals = self:at("=") and self:take("=") or false
    local initializer = equals and self:initializer() or false
    local semi = semicolon and self:take(";") or false
    return node("variable", typ, { typ = typ, name = name, dimensions = dimensions,
        equals = equals, initializer = initializer, semi = semi })
end
function P:initializer()
    if self:at("{") then return self:list("{", "}", P.initializer, true) end
    return self:expression()
end
function P:list(opening, closing, element, trailing)
    local left = self:take(opening)
    local elements, commas, final = {}, {}, false
    if not self:at(closing) then
        elements[1] = element(self)
        elements[1].first.allowed = true
        while self:at(",") do
            local comma = self:take(",")
            if trailing and self:at(closing) then
                comma.trailing_comma, final = true, comma
                break
            end
            commas[#commas + 1] = comma
            local item = element(self)
            item.first.allowed = true
            elements[#elements + 1] = item
        end
    end
    return node("list", left, { left = left, right = self:take(closing), elements = elements,
        commas = commas, trailing = final, role = opening })
end
function P:block()
    local left, statements = self:take("{"), {}
    while not self:at("}") and self:peek().kind ~= "end" do
        local stmt = self:statement()
        stmt.first.allowed = true
        statements[#statements + 1] = stmt
    end
    local right = self:take("}")
    right.allowed = true
    return node("block", left, { left = left, right = right, statements = statements })
end
function P:body()
    local result = self:statement()
    if result.tag ~= "block" then result.first.allowed = true end
    return result
end
function P:statement()
    local tok = self:peek()
    if self:at("{") then return self:block()
    elseif lexer.types[tok.text] then
        local typ, name = self:typ(), self:identifier()
        return self:variable(typ, name, true)
    elseif self:at("if") then return self:if_statement()
    elseif self:at("while") then
        local keyword, left = self:take("while"), self:take("(")
        local test, right = self:expression(), self:take(")")
        return node("while", keyword, { keyword = keyword, left = left, test = test,
            right = right, body = self:body() })
    elseif self:at("for") then return self:for_statement()
    elseif self:at("switch") then return self:switch_statement()
    elseif self:at("return") then
        local keyword = self:take("return")
        local expr = not self:at(";") and self:expression() or false
        return node("return", keyword, { keyword = keyword, expr = expr, semi = self:take(";") })
    elseif self:at("break") or self:at("continue") then
        self.cursor = self.cursor + 1
        return node("flow", tok, { keyword = tok, semi = self:take(";") })
    end
    local value = self:simple()
    return node("simple_stmt", value.first, { value = value, semi = self:take(";") })
end
function P:if_statement()
    local keyword, left = self:take("if"), self:take("(")
    local test, right = self:expression(), self:take(")")
    local body = self:body()
    local else_token = self:at("else") and self:take("else") or false
    local alternative = false
    if else_token then
        if self:at("if") then
            alternative = self:if_statement()
            alternative.first.allowed = false
        else alternative = self:body() end
    end
    return node("if", keyword, { keyword = keyword, left = left, test = test, right = right,
        body = body, else_token = else_token, alternative = alternative })
end
function P:for_statement()
    local keyword, left = self:take("for"), self:take("(")
    local initial = false
    if not self:at(";") then
        if lexer.types[self:peek().text] then
            local typ, name = self:typ(), self:identifier()
            initial = self:variable(typ, name, false)
        else initial = self:simple() end
    end
    local first_semi = self:take(";")
    local condition = not self:at(";") and self:expression() or false
    local second_semi = self:take(";")
    local update = not self:at(")") and self:simple() or false
    local right = self:take(")")
    return node("for", keyword, { keyword = keyword, left = left, initial = initial,
        first_semi = first_semi, condition = condition, second_semi = second_semi,
        update = update, right = right, body = self:body() })
end
function P:switch_statement()
    local keyword, left = self:take("switch"), self:take("(")
    local test, right = self:expression(), self:take(")")
    local opening, clauses = self:take("{"), {}
    while self:at("case") or self:at("default") do
        local label = self:peek()
        self.cursor, label.allowed = self.cursor + 1, true
        local value = label.text == "case" and self:expression() or false
        local colon, statements = self:take(":"), {}
        while not self:at("case") and not self:at("default") and not self:at("}") and self:peek().kind ~= "end" do
            local stmt = self:statement()
            stmt.first.allowed = true
            statements[#statements + 1] = stmt
        end
        clauses[#clauses + 1] = node("clause", label,
            { label = label, value = value, colon = colon, statements = statements })
    end
    local closing = self:take("}")
    closing.allowed = true
    return node("switch", keyword, { keyword = keyword, left = left, test = test, right = right,
        opening = opening, closing = closing, clauses = clauses })
end
function P:simple()
    local left = self:expression()
    if lexer.assignment[self:peek().text] then
        local op = self:peek()
        self.cursor = self.cursor + 1
        return node("assign", left.first, { left = left, op = op, right = self:expression() })
    end
    return node("expr_stmt", left.first, { expr = left })
end
function P:expression()
    local test = self:binary(1)
    if not self:at("?") then return test end
    local question, yes = self:take("?"), self:expression()
    local colon, no = self:take(":"), self:expression()
    return node("conditional", test.first, { test = test, question = question, yes = yes,
        colon = colon, no = no, level = 0 })
end
function P:binary(level)
    if level > 6 then return self:unary() end
    local left = self:binary(level + 1)
    while precedence[self:peek().text] == level do
        local op = self:peek()
        self.cursor = self.cursor + 1
        left = node("binary", left.first, { left = left, op = op,
            right = self:binary(level + 1), level = level })
    end
    return left
end
function P:unary()
    if self:at("-") or self:at("!") then
        local op = self:peek()
        self.cursor = self.cursor + 1
        return node("unary", op, { op = op, operand = self:unary(), level = 7 })
    end
    local target = self:primary()
    while true do
        if self:at("(") then
            target = node("call", target.first, { target = target,
                arguments = self:list("(", ")", P.expression, false), level = 8 })
        elseif self:at("[") then
            local left, index = self:take("["), self:expression()
            target = node("index", target.first, { target = target, left = left, index = index,
                right = self:take("]"), level = 8 })
        elseif self:at(".") then
            local dot, member = self:take("."), self:identifier()
            target = node("member", target.first, { target = target, dot = dot, member = member, level = 8 })
        else break end
    end
    return target
end
function P:primary()
    local tok = self:peek()
    if tok.kind == "identifier" or tok.kind == "number" or tok.kind == "string" or tok.text == "true" or tok.text == "false" then
        self.cursor = self.cursor + 1
        return node("primary", tok, { value = tok, level = 8 })
    elseif self:at("(") then
        local left, inner = self:take("("), self:expression()
        return node("paren", left, { left = left, inner = inner, right = self:take(")"), level = 8 })
    end
    self:fail("expression")
end

return function(tokens)
    local parser = setmetatable({ tokens = tokens, cursor = 1 }, P)
    local items = {}
    while parser:peek().kind ~= "end" do items[#items + 1] = parser:item() end
    return items
end
