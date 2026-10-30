local lexer = require("lexer")
local Parser = require("parser")
local A = {}
A.__index = A
local arithmetic = { ["+"] = true, ["-"] = true, ["*"] = true, ["/"] = true, ["%"] = true }
local relational = { ["<"] = true, ["<="] = true, [">"] = true, [">="] = true }
function A.can_complete(node)
    if node.completes ~= nil then return node.completes end
    local result = true
    if node.kind == "return" or node.kind == "break" or node.kind == "continue" then result = false
    elseif node.kind == "block" then
        for _, child in ipairs(node.statements) do if not A.can_complete(child) then result = false end end
    elseif node.kind == "if" and node.otherwise then
        local first, second = A.can_complete(node.consequent), A.can_complete(node.otherwise)
        result = first or second
    end
    node.completes = result
    return result
end
function A.new(declarations, end_position)
    return setmetatable({ declarations = declarations, end_position = end_position, globals = {},
        functions = {}, variables = {}, scopes = {} }, A)
end
function A:fail(position, message) lexer.fail("semantic", position, message) end
function A:prepare(node)
    node.references, node.read_accesses = {}, 0
    if node.kind == "function" then node.calls = {}; self.functions[#self.functions + 1] = node
    else self.variables[#self.variables + 1] = node end
end
function A:lookup(name, position, read)
    local referent
    for i = #self.scopes, 1, -1 do
        if self.scopes[i][name] then referent = self.scopes[i][name]; break end
    end
    referent = referent or self.globals[name]
    if referent then
        referent.references[#referent.references + 1] = position
        if read ~= false then referent.read_accesses = referent.read_accesses + 1 end
    end
    return referent
end
function A:variable(name, position, indexed, read)
    local referent = self:lookup(name, position, read)
    if not referent then self:fail(position, "undeclared identifier '" .. name .. "'") end
    if referent.kind == "function" then self:fail(position, "'" .. name .. "' is a function, not a variable") end
    local is_array = referent.kind == "global" and referent.size ~= nil
    if indexed and not is_array then self:fail(position, "'" .. name .. "' is not an array") end
    if not indexed and is_array then self:fail(position, "array '" .. name .. "' used without index") end
    return referent
end
function A:expression(node, call_statement)
    local kind, result = node.kind
    if kind == "integer" or kind == "read" then result = "int"
    elseif kind == "boolean" then result = "bool"
    elseif kind == "variable" or kind == "array" then
        node.referent = self:variable(node.name, node.position, kind == "array")
        if kind == "array" and self:expression(node.index) ~= "int" then
            self:fail(node.position, "index of '" .. node.name .. "' must be int")
        end
        result = node.referent.type
    elseif kind == "call" then
        local referent = self:lookup(node.name, node.position)
        if not referent then self:fail(node.position, "undeclared function '" .. node.name .. "'") end
        if referent.kind ~= "function" then self:fail(node.position, "'" .. node.name .. "' is not a function") end
        node.referent, self.current_function.calls[referent] = referent, true
        if #node.arguments ~= #referent.parameters then
            self:fail(node.position, string.format("wrong number of arguments to '%s' (expected %d, found %d)", node.name, #referent.parameters, #node.arguments))
        end
        for k, argument in ipairs(node.arguments) do
            if self:expression(argument) ~= referent.parameters[k].type then
                self:fail(node.position, string.format("argument %d of '%s' must be %s", k, node.name, referent.parameters[k].type))
            end
        end
        if not call_statement and referent.type == "void" then self:fail(node.position, "void function '" .. node.name .. "' used as a value") end
        result = referent.type
    elseif kind == "unary" then
        result = self:expression(node.operand)
        local required = node.operator == "-" and "int" or "bool"
        if result ~= required then self:fail(node.position, "operator '" .. node.operator .. "' requires " .. required .. " operand") end
    else
        local left = self:expression(node.left)
        local right = self:expression(node.right)
        local operator = node.operator
        if arithmetic[operator] or relational[operator] then
            if left ~= "int" or right ~= "int" then self:fail(node.position, "operator '" .. operator .. "' requires int operands") end
            result = arithmetic[operator] and "int" or "bool"
        elseif operator == "==" or operator == "!=" then
            if left ~= right then self:fail(node.position, "operator '" .. operator .. "' requires operands of the same type") end
            result = "bool"
        else
            if left ~= "bool" or right ~= "bool" then self:fail(node.position, "operator '" .. operator .. "' requires bool operands") end
            result = "bool"
        end
    end
    node.type = result
    return result
end
function A:constant_initializer(node)
    local first
    local function visit(current)
        local kind = current.kind
        if kind == "variable" or kind == "array" or kind == "call" or kind == "read" then
            local p = current.position
            if not first or p[1] < first[1] or (p[1] == first[1] and p[2] < first[2]) then first = p end
        end
        for _, child in ipairs(Parser.expression_children(current)) do visit(child) end
    end
    visit(node)
    if first then self:fail(first, "global initializer must be constant") end
    return self:expression(node)
end
function A:statement(node, loop_depth)
    loop_depth = loop_depth or 0
    local kind = node.kind
    if kind == "declaration" then
        local scope = self.scopes[#self.scopes]
        if node.type == "void" then self:fail(node.name_position, "variable '" .. node.name .. "' cannot have type void") end
        if scope[node.name] then self:fail(node.name_position, "redeclaration of '" .. node.name .. "'") end
        if node.initializer and self:expression(node.initializer) ~= node.type then
            self:fail(node.name_position, "type mismatch in initialization of '" .. node.name .. "'")
        end
        self:prepare(node)
        scope[node.name] = node
    elseif kind == "assignment" then
        node.referent = self:variable(node.name, node.position, node.index ~= nil, false)
        if node.index and self:expression(node.index) ~= "int" then self:fail(node.position, "index of '" .. node.name .. "' must be int") end
        if self:expression(node.value) ~= node.referent.type then self:fail(node.position, "type mismatch in assignment to '" .. node.name .. "'") end
    elseif kind == "call_statement" then self:expression(node.expression, true)
    elseif kind == "if" or kind == "while" then
        if self:expression(node.condition) ~= "bool" then self:fail(node.position, "condition of '" .. kind .. "' must be bool") end
        if kind == "if" then
            self:statement(node.consequent, loop_depth)
            if node.otherwise then self:statement(node.otherwise, loop_depth) end
        else self:statement(node.body, loop_depth + 1) end
    elseif kind == "for" then
        self.scopes[#self.scopes + 1] = {}
        if node.initial then self:statement(node.initial, loop_depth) end
        if node.condition and self:expression(node.condition) ~= "bool" then self:fail(node.position, "condition of 'for' must be bool") end
        if node.update then self:statement(node.update, loop_depth) end
        self:statement(node.body, loop_depth + 1)
        table.remove(self.scopes)
    elseif kind == "break" or kind == "continue" then
        if loop_depth == 0 then self:fail(node.position, "'" .. kind .. "' outside loop") end
    elseif kind == "return" then
        local fn = self.current_function
        if fn.type == "void" and node.value then self:fail(node.position, "function '" .. fn.name .. "' must not return a value") end
        if fn.type ~= "void" then
            if not node.value then self:fail(node.position, "function '" .. fn.name .. "' must return a value") end
            if self:expression(node.value) ~= fn.type then self:fail(node.position, "return value of '" .. fn.name .. "' must be " .. fn.type) end
        end
    elseif kind == "print" then
        for k, argument in ipairs(node.arguments) do
            if self:expression(argument) ~= "int" then self:fail(node.position, "argument " .. k .. " of 'print' must be int") end
        end
    elseif kind == "block" then
        self.scopes[#self.scopes + 1] = {}
        for _, child in ipairs(node.statements) do self:statement(child, loop_depth) end
        table.remove(self.scopes)
    end
end
function A:analyze()
    for _, node in ipairs(self.declarations) do
        if node.kind == "global" then
            if node.size ~= nil then
                if node.type ~= "int" then self:fail(node.name_position, "array '" .. node.name .. "' must have element type int") end
                if node.size == 0 then self:fail(node.size_position, "array '" .. node.name .. "' must have a positive size") end
            elseif node.type == "void" then self:fail(node.name_position, "variable '" .. node.name .. "' cannot have type void") end
        end
        if self.globals[node.name] then self:fail(node.name_position, "redeclaration of '" .. node.name .. "'") end
        if node.kind == "global" then
            if node.initializer and self:constant_initializer(node.initializer) ~= node.type then
                self:fail(node.name_position, "type mismatch in initialization of '" .. node.name .. "'")
            end
        else
            local names = {}
            for _, parameter in ipairs(node.parameters) do
                if parameter.type == "void" then self:fail(parameter.name_position, "parameter '" .. parameter.name .. "' cannot have type void") end
                if names[parameter.name] then self:fail(parameter.name_position, "redeclaration of '" .. parameter.name .. "'") end
                names[parameter.name] = true
                self:prepare(parameter)
            end
        end
        self:prepare(node)
        self.globals[node.name] = node
    end
    local main = self.globals.main
    if not main or main.kind ~= "function" then self:fail(self.end_position, "no main function") end
    if main.type ~= "void" or #main.parameters > 0 then self:fail(main.name_position, "main must be declared as 'void main()'") end
    for _, fn in ipairs(self.functions) do
        self.current_function, self.scopes = fn, { {} }
        for _, parameter in ipairs(fn.parameters) do self.scopes[1][parameter.name] = parameter end
        for _, statement in ipairs(fn.body.statements) do self:statement(statement) end
        if fn.type ~= "void" and A.can_complete(fn.body) then self:fail(fn.name_position, "missing return in function '" .. fn.name .. "'") end
    end
    return self
end
return A
