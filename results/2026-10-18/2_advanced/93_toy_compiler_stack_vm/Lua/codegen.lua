local Parser = require("parser")
local G = {}
G.__index = G
G.binary = { ["+"] = "ADD", ["-"] = "SUB", ["*"] = "MUL", ["/"] = "DIV", ["%"] = "MOD",
    ["<"] = "LT", ["<="] = "LE", [">"] = "GT", [">="] = "GE", ["=="] = "EQ", ["!="] = "NE" }
G.jumps = { JUMP = true, JUMPF = true, JUMPT = true }
G.conditional = { JUMPF = true, JUMPT = true }
G.transfers = { JUMP = true, RET = true, RETV = true, HALT = true }
G.negated = { LT = "GE", LE = "GT", GT = "LE", GE = "LT", EQ = "NE", NE = "EQ" }
G.inverse = { JUMPF = "JUMPT", JUMPT = "JUMPF" }
function G.instruction(op, args, position) return { op = op, args = args or {}, position = position } end
function G.new() return setmetatable({ code = {}, loops = {} }, G) end
function G:emit(op, position, ...) self.code[#self.code + 1] = G.instruction(op, { ... }, position) end
function G:mark(label) label.position = #self.code + 1 end
function G:finish()
    local result = {}
    for i, instruction in ipairs(self.code) do
        local args = G.jumps[instruction.op] and { assert(instruction.args[1].position) } or instruction.args
        result[i] = G.instruction(instruction.op, args, instruction.position)
    end
    return result
end
function G:expression(node)
    local kind, position = node.kind, node.position
    if kind == "integer" then self:emit("PUSH", position, node.value)
    elseif kind == "boolean" then self:emit("PUSH", position, node.value and 1 or 0)
    elseif kind == "variable" then
        local ref = node.referent
        if ref.kind == "global" then self:emit("LOADG", position, ref.address)
        else self:emit("LOADL", position, ref.slot) end
    elseif kind == "array" then
        self:expression(node.index)
        self:emit("LOADA", position, node.referent.address, node.referent.size)
    elseif kind == "read" then self:emit("READ", position)
    elseif kind == "call" then
        for _, argument in ipairs(node.arguments) do self:expression(argument) end
        self:emit("CALL", position, node.referent.name, #node.arguments)
    elseif kind == "unary" then
        self:expression(node.operand)
        self:emit(node.operator == "-" and "NEG" or "NOT", position)
    elseif node.operator == "&&" or node.operator == "||" then
        local shortcut, ending = {}, {}
        self:expression(node.left)
        self:emit(node.operator == "&&" and "JUMPF" or "JUMPT", position, shortcut)
        self:expression(node.right)
        self:emit("JUMP", position, ending)
        self:mark(shortcut)
        self:emit("PUSH", position, node.operator == "||" and 1 or 0)
        self:mark(ending)
    else
        self:expression(node.left)
        self:expression(node.right)
        self:emit(G.binary[node.operator], position)
    end
end
function G:statement(node)
    local kind, position = node.kind, node.position
    if kind == "declaration" then
        if node.initializer then self:expression(node.initializer) else self:emit("PUSH", node.name_position, 0) end
        self:emit("STOREL", node.name_position, node.slot)
    elseif kind == "assignment" then
        if node.index then self:expression(node.index) end
        self:expression(node.value)
        local ref = node.referent
        if node.index then self:emit("STOREA", position, ref.address, ref.size)
        elseif ref.kind == "global" then self:emit("STOREG", position, ref.address)
        else self:emit("STOREL", position, ref.slot) end
    elseif kind == "call_statement" then
        self:expression(node.expression)
        if node.expression.type ~= "void" then self:emit("POP", position) end
    elseif kind == "print" then
        for _, argument in ipairs(node.arguments) do self:expression(argument) end
        self:emit("PRINT", position, #node.arguments)
    elseif kind == "if" then
        local alternative, ending = {}, {}
        self:expression(node.condition)
        self:emit("JUMPF", position, alternative)
        self:statement(node.consequent)
        if not node.otherwise then self:mark(alternative)
        else
            self:emit("JUMP", position, ending)
            self:mark(alternative)
            self:statement(node.otherwise)
            self:mark(ending)
        end
    elseif kind == "while" then
        local start, ending = {}, {}
        self:mark(start)
        self:expression(node.condition)
        self:emit("JUMPF", position, ending)
        self.loops[#self.loops + 1] = { ending, start }
        self:statement(node.body)
        table.remove(self.loops)
        self:emit("JUMP", position, start)
        self:mark(ending)
    elseif kind == "for" then
        local start, update, ending = {}, {}, {}
        if node.initial then self:statement(node.initial) end
        self:mark(start)
        if node.condition then self:expression(node.condition); self:emit("JUMPF", position, ending) end
        self.loops[#self.loops + 1] = { ending, update }
        self:statement(node.body)
        table.remove(self.loops)
        self:mark(update)
        if node.update then self:statement(node.update) end
        self:emit("JUMP", position, start)
        self:mark(ending)
    elseif kind == "break" or kind == "continue" then
        self:emit("JUMP", position, self.loops[#self.loops][kind == "continue" and 2 or 1])
    elseif kind == "return" then
        if node.value then self:expression(node.value); self:emit("RETV", position) else self:emit("RET", position) end
    elseif kind == "block" then for _, child in ipairs(node.statements) do self:statement(child) end end
end
local function assign_slots(fn)
    local declarations = {}
    local function visit(node)
        if node.kind == "declaration" then declarations[#declarations + 1] = node end
        for _, child in ipairs(Parser.statement_children(node)) do visit(child) end
    end
    visit(fn.body)
    table.sort(declarations, function(a, b)
        return a.name_position[1] < b.name_position[1]
            or (a.name_position[1] == b.name_position[1] and a.name_position[2] < b.name_position[2])
    end)
    local slots = { table.unpack(fn.parameters) }
    for _, declaration in ipairs(declarations) do slots[#slots + 1] = declaration end
    for i, declaration in ipairs(slots) do declaration.slot = i - 1 end
    return slots
end
function G.generate(globals, functions, main)
    local address, initialization = 0, G.new()
    for _, variable in ipairs(globals) do
        variable.address = address
        address = address + (variable.size or 1)
    end
    for _, variable in ipairs(globals) do
        if variable.initializer then
            initialization:expression(variable.initializer)
            initialization:emit("STOREG", variable.name_position, variable.address)
        end
    end
    initialization:emit("CALL", main.name_position, "main", 0)
    initialization:emit("HALT", main.name_position)
    local units = { { name = "<init>", slots = {}, before = initialization:finish() } }
    for _, fn in ipairs(functions) do
        local slots, generator = assign_slots(fn), G.new()
        generator:emit("ENTER", fn.name_position, #slots)
        generator:statement(fn.body)
        if fn.type == "void" then generator:emit("RET", fn.body.end_position) end
        units[#units + 1] = { name = fn.name, fn = fn, slots = slots, before = generator:finish() }
    end
    return units, address
end
return G
