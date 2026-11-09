local L = require("lexer")
local P = {}
P.__index = P
P.assignments = { ["="] = true, ["+="] = true, ["-="] = true, ["*="] = true, ["/="] = true, ["%="] = true, ["^="] = true }
P.comparisons = { ["<"] = true, ["<="] = true, ["=="] = true, ["!="] = true, [">="] = true, [">"] = true }
P.statements = { ["if"] = true, ["while"] = true, ["do"] = true, ["for"] = true, for_in = true, print = true,
    printf = true, delete = true, next = true, ["break"] = true, ["continue"] = true, exit = true, ["return"] = true, expression_statement = true }
local lvalues = { name = true, array = true, field = true }
local function node(kind, position, children, fields)
    fields = fields or {}
    fields.kind, fields.position, fields.children = kind, position, {}
    for _, child in ipairs(children or {}) do if child then fields.children[#fields.children + 1] = child end end
    return fields
end
function P.new(tokens) return setmetatable({ tokens = tokens, cursor = 1, in_function = false, phase = false, loop_depth = 0 }, P) end
function P:peek() return self.tokens[self.cursor] end
function P:take()
    local token = self:peek()
    self.cursor = self.cursor + 1
    return token
end
function P:fail(position) L.fail(position or self:peek().position) end
function P:accept(spelling) if self:peek().spelling == spelling then return self:take() end; return false end
function P:expect(spelling) if self:peek().spelling ~= spelling then self:fail() end; return self:take() end
function P:name()
    if self:peek().kind ~= "name" then self:fail() end
    local token = self:take()
    return node("name", token.position, {}, { name = token.spelling })
end
function P:newlines() while self:accept("\n") do end end
function P:parse()
    local items = {}
    while self:peek().kind ~= "end" do
        if self:peek().spelling == "\n" or self:peek().spelling == ";" then self:take()
        else
            local start = self:peek()
            if self:accept("function") then
                if self:peek().kind ~= "name" and self:peek().kind ~= "function_name" then self:fail() end
                local name = self:take()
                self:expect("(")
                local parameters = {}
                if self:peek().spelling ~= ")" then
                    repeat
                        local parameter = self:name()
                        parameter.kind = "parameter"
                        parameters[#parameters + 1] = parameter
                        if not self:accept(",") then break end
                        self:newlines()
                    until false
                end
                self:expect(")")
                self:newlines()
                self.in_function = true
                local body = self:block()
                self.in_function = false
                local children = { table.unpack(parameters) }
                children[#children + 1] = body
                items[#items + 1] = node("function", start.position, children, { name = name.spelling, name_position = name.position, parameters = parameters, body = body })
            else
                local patterns, flavor = {}, false
                if start.spelling == "BEGIN" or start.spelling == "END" then flavor = self:take().spelling
                elseif start.spelling == "{" then flavor = "all"
                else
                    patterns[1] = self:expression()
                    if self:accept(",") then self:newlines(); patterns[2] = self:expression() end
                    flavor = #patterns == 2 and "range" or "pattern"
                end
                self.phase = flavor
                local action = false
                if flavor == "BEGIN" or flavor == "END" or flavor == "all" or self:peek().spelling == "{" then action = self:block()
                elseif self:peek().spelling ~= "\n" and self:peek().spelling ~= ";" and self:peek().kind ~= "end" then self:fail() end
                self.phase = false
                local children = { table.unpack(patterns) }
                children[#children + 1] = action
                items[#items + 1] = node("rule", start.position, children, { flavor = flavor, patterns = patterns, action = action })
            end
        end
    end
    return items
end
function P:block()
    local opening, statements = self:expect("{"), {}
    while self:peek().spelling ~= "}" do
        if self:peek().spelling == "\n" or self:peek().spelling == ";" then self:take()
        else statements[#statements + 1] = self:statement() end
    end
    self:expect("}")
    return node("block", opening.position, statements, { statements = statements })
end
function P:condition()
    self:expect("(")
    local value = self:expression()
    self:expect(")")
    return value
end
function P:loop_body()
    self:newlines()
    self.loop_depth = self.loop_depth + 1
    local body = self:statement()
    self.loop_depth = self.loop_depth - 1
    return body
end
function P:terminator()
    if self:peek().spelling == ";" or self:peek().spelling == "\n" then self:take()
    elseif self:peek().spelling ~= "}" then self:fail() end
end
function P:statement()
    local token = self:peek()
    local spelling = token.spelling
    if spelling == "{" then return self:block()
    elseif self:accept(";") then return node("empty", token.position)
    elseif self:accept("if") then
        local condition = self:condition()
        self:newlines()
        local first = self:statement()
        self:newlines()
        local second = false
        if self:accept("else") then self:newlines(); second = self:statement() end
        return node("if", token.position, { condition, first, second }, { condition = condition, first = first, second = second })
    elseif self:accept("while") then
        local condition, body = self:condition(), self:loop_body()
        return node("while", token.position, { condition, body }, { condition = condition, body = body })
    elseif self:accept("do") then
        local body = self:loop_body()
        self:newlines()
        self:expect("while")
        local condition = self:condition()
        self:terminator()
        return node("do", token.position, { body, condition }, { body = body, condition = condition })
    elseif self:accept("for") then
        self:expect("(")
        local a, b, c, d = self.tokens[self.cursor], self.tokens[self.cursor + 1], self.tokens[self.cursor + 2], self.tokens[self.cursor + 3]
        if d and a.kind == "name" and b.spelling == "in" and c.kind == "name" and d.spelling == ")" then
            local variable = self:name()
            self:expect("in")
            local array = self:name()
            self:expect(")")
            local body = self:loop_body()
            return node("for_in", token.position, { variable, array, body }, { variable = variable, array = array, body = body })
        end
        local initial = self:peek().spelling ~= ";" and self:expression() or false
        self:expect(";")
        self:newlines()
        local condition = self:peek().spelling ~= ";" and self:expression() or false
        self:expect(";")
        self:newlines()
        local update = self:peek().spelling ~= ")" and self:expression() or false
        self:expect(")")
        local body = self:loop_body()
        return node("for", token.position, { initial, condition, update, body }, { initial = initial, condition = condition, update = update, body = body })
    end
    local result
    if spelling == "print" or spelling == "printf" then self:take(); result = self:output_statement(token)
    elseif spelling == "delete" then
        self:take()
        local array, indexes = self:name(), false
        if self:accept("[") then indexes = self:expression_list(); self:expect("]") end
        local children = { array }
        if indexes then for _, index in ipairs(indexes) do children[#children + 1] = index end end
        result = node("delete", token.position, children, { array = array, indexes = indexes })
    elseif spelling == "next" or spelling == "break" or spelling == "continue" or spelling == "exit" or spelling == "return" then
        self:take()
        if spelling == "next" and not self.in_function and (self.phase == "BEGIN" or self.phase == "END") then self:fail(token.position) end
        if spelling == "return" and not self.in_function then self:fail(token.position) end
        if (spelling == "break" or spelling == "continue") and self.loop_depth == 0 then self:fail(token.position) end
        local value = false
        if (spelling == "exit" or spelling == "return") and self:peek().spelling ~= ";" and self:peek().spelling ~= "\n" and self:peek().spelling ~= "}" then value = self:expression() end
        result = node(spelling, token.position, { value }, { value = value })
    else
        local expression = self:expression()
        result = node("expression_statement", token.position, { expression }, { expression = expression })
    end
    self:terminator()
    return result
end
function P:parenthesized_output()
    if self:peek().spelling ~= "(" then return false end
    local depth = 0
    for i = self.cursor, #self.tokens do
        local spelling = self.tokens[i].spelling
        if spelling == "(" then depth = depth + 1
        elseif spelling == ")" then
            depth = depth - 1
            if depth == 0 then
                local following = self.tokens[i + 1]
                return following and (following.spelling == ";" or following.spelling == "\n" or following.spelling == "}"
                    or following.spelling == ">" or following.spelling == ">>" or following.kind == "end") or false
            end
        end
    end
    return false
end
function P:output_statement(token)
    local arguments = {}
    if self:parenthesized_output() then self:expect("("); arguments = self:expression_list(); self:expect(")")
    elseif self:peek().spelling ~= ";" and self:peek().spelling ~= "\n" and self:peek().spelling ~= "}"
        and self:peek().spelling ~= ">" and self:peek().spelling ~= ">>" then arguments = self:expression_list(false) end
    if token.spelling == "printf" and #arguments == 0 then self:fail() end
    local redirect = (self:peek().spelling == ">" or self:peek().spelling == ">>") and self:take() or false
    local filename = redirect and self:concatenation() or false
    local children = { table.unpack(arguments) }
    children[#children + 1] = filename
    return node(token.spelling, token.position, children, { arguments = arguments, redirect = redirect and redirect.spelling or false,
        redirect_position = redirect and redirect.position or false, filename = filename })
end
function P:expression_list(greater)
    if greater == nil then greater = true end
    local result = { self:expression(greater) }
    while self:accept(",") do self:newlines(); result[#result + 1] = self:expression(greater) end
    return result
end
function P:expression(greater)
    if greater == nil then greater = true end
    local left = self:conditional(greater)
    if lvalues[left.kind] and P.assignments[self:peek().spelling] then
        local operator = self:take()
        local right = self:expression(greater)
        return node("assignment", operator.position, { left, right }, { operator = operator.spelling, location = left, value = right })
    end
    return left
end
function P:conditional(greater)
    local condition = self:logical(1, greater)
    local operator = self:accept("?")
    if not operator then return condition end
    local first = self:conditional(greater)
    self:expect(":")
    local second = self:conditional(greater)
    return node("conditional", operator.position, { condition, first, second }, { condition = condition, first = first, second = second })
end
function P:binary(operator, left, right)
    return node("binary", operator.position, { left, right }, { operator = operator.spelling, left = left, right = right })
end
function P:logical(level, greater)
    if level == 3 then return self:membership(greater) end
    local operator_name = level == 1 and "||" or "&&"
    local left = self:logical(level + 1, greater)
    while self:peek().spelling == operator_name do
        local operator = self:take()
        self:newlines()
        left = self:binary(operator, left, self:logical(level + 1, greater))
    end
    return left
end
function P:membership(greater)
    local left = self:comparison(greater)
    while self:peek().spelling == "in" do
        local operator, array = self:take(), self:name()
        left = node("membership", operator.position, { left, array }, { indexes = { left }, array = array })
    end
    return left
end
function P:comparison(greater)
    local left = self:concatenation()
    while P.comparisons[self:peek().spelling] and (greater or self:peek().spelling ~= ">") do
        local operator = self:take()
        left = self:binary(operator, left, self:concatenation())
    end
    return left
end
function P:concatenation()
    local left = self:additive()
    local function starts(token)
        return token.kind == "number" or token.kind == "string" or token.kind == "name" or token.kind == "function_name"
            or token.kind == "builtin" or token.spelling == "$" or token.spelling == "(" or token.spelling == "++" or token.spelling == "--"
    end
    while starts(self:peek()) do
        local position = self:peek().position
        local right = self:additive()
        left = node("binary", position, { left, right }, { operator = "concat", left = left, right = right })
    end
    return left
end
function P:additive()
    local left = self:multiplicative()
    while self:peek().spelling == "+" or self:peek().spelling == "-" do
        local operator = self:take()
        left = self:binary(operator, left, self:multiplicative())
    end
    return left
end
function P:multiplicative()
    local left = self:unary()
    while self:peek().spelling == "*" or self:peek().spelling == "/" or self:peek().spelling == "%" do
        local operator = self:take()
        left = self:binary(operator, left, self:unary())
    end
    return left
end
function P:unary()
    local spelling = self:peek().spelling
    if spelling == "!" or spelling == "-" or spelling == "+" then
        local operator = self:take()
        local operand = self:unary()
        return node("unary", operator.position, { operand }, { operator = operator.spelling, operand = operand })
    end
    local left = self:postfix()
    if self:peek().spelling == "^" then
        local operator = self:take()
        left = self:binary(operator, left, self:unary())
    end
    return left
end
function P:prefix()
    local operator = self:take()
    local location = self:lvalue()
    return node("increment", operator.position, { location }, { location = location, delta = operator.spelling == "++" and 1 or -1, prefix = true })
end
function P:postfix()
    if self:peek().spelling == "++" or self:peek().spelling == "--" then return self:prefix() end
    local left = self:atom()
    if lvalues[left.kind] and (self:peek().spelling == "++" or self:peek().spelling == "--") then
        local operator = self:take()
        return node("increment", operator.position, { left }, { location = left, delta = operator.spelling == "++" and 1 or -1, prefix = false })
    end
    return left
end
function P:lvalue()
    if self:peek().kind == "name" then
        local name = self:name()
        if self:accept("[") then
            local indexes = self:expression_list()
            self:expect("]")
            return node("array", name.position, indexes, { name = name.name, indexes = indexes })
        end
        return name
    end
    local dollar = self:accept("$")
    if dollar then
        local index = (self:peek().spelling == "++" or self:peek().spelling == "--") and self:prefix() or self:atom()
        return node("field", dollar.position, { index }, { index = index })
    end
    self:fail()
end
function P:atom()
    local token = self:peek()
    if token.kind == "number" or token.kind == "string" then self:take(); return node(token.kind, token.position, {}, { value = token.value })
    elseif token.kind == "name" or token.spelling == "$" then return self:lvalue()
    elseif self:accept("(") then
        local expressions = self:expression_list()
        self:expect(")")
        if #expressions == 1 then return node("paren", token.position, expressions, { expression = expressions[1] }) end
        self:expect("in")
        local array = self:name()
        local children = { table.unpack(expressions) }
        children[#children + 1] = array
        return node("membership", token.position, children, { indexes = expressions, array = array })
    elseif token.kind == "function_name" or token.kind == "builtin" then
        self:take()
        local arguments = {}
        if self:accept("(") then
            if self:peek().spelling ~= ")" then arguments = self:expression_list() end
            self:expect(")")
        elseif token.kind == "function_name" or token.spelling ~= "length" then self:fail() end
        local kind = token.kind == "function_name" and "call" or "builtin"
        if kind == "builtin" then self:check_builtin(token, arguments) end
        return node(kind, token.position, arguments, { name = token.spelling, arguments = arguments })
    elseif self:accept("getline") then
        local target = (self:peek().kind == "name" or self:peek().spelling == "$") and self:lvalue() or false
        local filename = self:accept("<") and self:atom() or false
        return node("getline", token.position, { target, filename }, { target = target, filename = filename })
    end
    self:fail()
end
function P:check_builtin(token, arguments)
    local count, name, valid = #arguments, token.spelling, false
    if name == "length" then valid = count == 0 or count == 1
    elseif name == "substr" or name == "split" then valid = count == 2 or count == 3
    elseif name == "index" then valid = count == 2
    elseif name == "sprintf" then valid = count >= 1
    else valid = count == 1 end
    if not valid or (name == "split" and arguments[2].kind ~= "name") then self:fail(token.position) end
end
return P
