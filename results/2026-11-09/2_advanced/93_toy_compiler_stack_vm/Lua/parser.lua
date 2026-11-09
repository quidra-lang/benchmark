local lexer = require("lexer")
local P = {}
P.__index = P
P.types = { int = true, bool = true, void = true }
local operators = { { ["||"] = true }, { ["&&"] = true }, { ["=="] = true, ["!="] = true },
    { ["<"] = true, ["<="] = true, [">"] = true, [">="] = true }, { ["+"] = true, ["-"] = true },
    { ["*"] = true, ["/"] = true, ["%"] = true } }
function P.node(kind, position, fields)
    fields = fields or {}
    fields.kind, fields.position = kind, position
    return fields
end
function P.expression_children(node)
    if node.kind == "binary" then return { node.left, node.right }
    elseif node.kind == "unary" then return { node.operand }
    elseif node.kind == "array" then return { node.index }
    elseif node.kind == "call" then return node.arguments end
    return {}
end
function P.statement_children(node)
    if node.kind == "block" then return node.statements
    elseif node.kind == "if" then
        local result = { node.consequent }
        if node.otherwise then result[#result + 1] = node.otherwise end
        return result
    elseif node.kind == "while" then return { node.body }
    elseif node.kind == "for" then
        local result = {}
        if node.initial then result[#result + 1] = node.initial end
        if node.update then result[#result + 1] = node.update end
        result[#result + 1] = node.body
        return result
    end
    return {}
end
function P.new(tokens) return setmetatable({ tokens = tokens, cursor = 1 }, P) end
function P:peek() return self.tokens[self.cursor] end
function P:fail()
    local tok = self:peek()
    lexer.fail("syntax", tok.position, tok.kind == "end" and "unexpected end of program" or "unexpected '" .. tok.spelling .. "'")
end
function P:take()
    local tok = self:peek()
    self.cursor = self.cursor + 1
    return tok
end
function P:accept(spelling)
    if self:peek().spelling == spelling then return self:take() end
    return false
end
function P:expect(spelling)
    if self:peek().spelling ~= spelling then self:fail() end
    return self:take()
end
function P:head()
    if not P.types[self:peek().spelling] then self:fail() end
    local typ = self:take()
    if self:peek().kind ~= "identifier" then self:fail() end
    local name = self:take()
    return typ.position, { type = typ.spelling, name = name.spelling, name_position = name.position }
end
function P:parse()
    local declarations = {}
    while self:peek().kind ~= "end" do
        local position, fields = self:head()
        if self:accept("(") then
            fields.parameters = {}
            if self:peek().spelling ~= ")" then
                repeat
                    local p, f = self:head()
                    fields.parameters[#fields.parameters + 1] = P.node("parameter", p, f)
                until not self:accept(",")
            end
            self:expect(")")
            fields.body = self:block()
            declarations[#declarations + 1] = P.node("function", position, fields)
        else
            if self:accept("[") then
                if self:peek().kind ~= "integer" then self:fail() end
                local tok = self:take()
                fields.size, fields.size_position = tonumber(tok.spelling), tok.position
                self:expect("]")
            elseif self:accept("=") then fields.initializer = self:expression() end
            self:expect(";")
            declarations[#declarations + 1] = P.node("global", position, fields)
        end
    end
    return declarations
end
function P:declaration(for_initial)
    local position, fields = self:head()
    if for_initial then self:expect("="); fields.initializer = self:expression()
    else
        if self:accept("=") then fields.initializer = self:expression() end
        self:expect(";")
    end
    return P.node("declaration", position, fields)
end
function P:block()
    local opening, statements = self:expect("{"), {}
    while self:peek().spelling ~= "}" do
        statements[#statements + 1] = P.types[self:peek().spelling] and self:declaration() or self:statement()
    end
    local closing = self:expect("}")
    return P.node("block", opening.position, { statements = statements, end_position = closing.position })
end
function P:statement()
    local tok, fields = self:peek(), {}
    local spelling = tok.spelling
    if spelling == "{" then return self:block()
    elseif spelling == "if" or spelling == "while" then
        self:take()
        self:expect("(")
        fields.condition = self:expression()
        self:expect(")")
        local body = self:statement()
        if spelling == "while" then fields.body = body
        else
            fields.consequent = body
            if self:accept("else") then fields.otherwise = self:statement() end
        end
    elseif spelling == "for" then
        self:take()
        self:expect("(")
        if P.types[self:peek().spelling] then fields.initial = self:declaration(true)
        elseif self:peek().spelling ~= ";" then fields.initial = self:simple() end
        self:expect(";")
        if self:peek().spelling ~= ";" then fields.condition = self:expression() end
        self:expect(";")
        if self:peek().spelling ~= ")" then fields.update = self:simple() end
        self:expect(")")
        fields.body = self:statement()
    elseif spelling == "break" or spelling == "continue" then self:take(); self:expect(";")
    elseif spelling == "return" then
        self:take()
        if self:peek().spelling ~= ";" then fields.value = self:expression() end
        self:expect(";")
    elseif spelling == "print" then
        self:take()
        self:expect("(")
        fields.arguments = { self:expression() }
        while self:accept(",") do fields.arguments[#fields.arguments + 1] = self:expression() end
        self:expect(")")
        self:expect(";")
    elseif tok.kind == "identifier" or spelling == "read" then
        local result = self:simple()
        self:expect(";")
        return result
    else self:fail() end
    return P.node(spelling, tok.position, fields)
end
function P:simple()
    local tok = self:peek()
    if tok.kind ~= "identifier" and tok.spelling ~= "read" then self:fail() end
    local value = self:primary()
    if value.kind == "call" or value.kind == "read" then
        return P.node("call_statement", value.position, { expression = value })
    end
    self:expect("=")
    return P.node("assignment", value.position, { name = value.name, index = value.index, value = self:expression() })
end
function P:expression(level)
    level = level or 1
    if level == 7 then
        if self:peek().spelling == "-" or self:peek().spelling == "!" then
            local operator = self:take()
            return P.node("unary", operator.position, { operator = operator.spelling, operand = self:expression(level) })
        end
        return self:primary()
    end
    local result = self:expression(level + 1)
    while operators[level][self:peek().spelling] do
        local operator = self:take()
        result = P.node("binary", operator.position, { operator = operator.spelling, left = result, right = self:expression(level + 1) })
    end
    return result
end
function P:primary()
    local tok = self:peek()
    if tok.kind == "integer" then self:take(); return P.node("integer", tok.position, { value = tonumber(tok.spelling) })
    elseif tok.spelling == "true" or tok.spelling == "false" then
        self:take()
        return P.node("boolean", tok.position, { value = tok.spelling == "true" })
    elseif tok.spelling == "read" then
        self:take(); self:expect("("); self:expect(")")
        return P.node("read", tok.position)
    elseif self:accept("(") then
        local result = self:expression()
        self:expect(")")
        return result
    elseif tok.kind == "identifier" then
        self:take()
        if self:accept("(") then
            local arguments = {}
            if self:peek().spelling ~= ")" then
                arguments[1] = self:expression()
                while self:accept(",") do arguments[#arguments + 1] = self:expression() end
            end
            self:expect(")")
            return P.node("call", tok.position, { name = tok.spelling, arguments = arguments })
        elseif self:accept("[") then
            local index = self:expression()
            self:expect("]")
            return P.node("array", tok.position, { name = tok.spelling, index = index })
        end
        return P.node("variable", tok.position, { name = tok.spelling })
    end
    self:fail()
end
return P
