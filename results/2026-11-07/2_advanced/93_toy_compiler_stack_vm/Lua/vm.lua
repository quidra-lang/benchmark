local V = {}
V.__index = V
V.binary = { ADD = true, SUB = true, MUL = true, DIV = true, MOD = true, LT = true,
    LE = true, GT = true, GE = true, EQ = true, NE = true }
local function trunc_div(a, b)
    local quotient = math.abs(a) // math.abs(b)
    return (a < 0) ~= (b < 0) and -quotient or quotient
end
function V.calculate(op, a, b)
    if (op == "DIV" or op == "MOD") and b == 0 then return nil, "division by zero" end
    local value
    if op == "ADD" then value = a + b
    elseif op == "SUB" then value = a - b
    elseif op == "MUL" then value = a * b
    elseif op == "DIV" then value = trunc_div(a, b)
    elseif op == "MOD" then value = a - trunc_div(a, b) * b
    elseif op == "NEG" then value = -a
    elseif op == "NOT" then value = a == 0 and 1 or 0
    elseif op == "LT" then value = a < b and 1 or 0
    elseif op == "LE" then value = a <= b and 1 or 0
    elseif op == "GT" then value = a > b and 1 or 0
    elseif op == "GE" then value = a >= b and 1 or 0
    elseif op == "EQ" then value = a == b and 1 or 0
    elseif op == "NE" then value = a ~= b and 1 or 0
    else error("unknown arithmetic instruction " .. op) end
    if value < -2147483648 or value > 2147483647 then return nil, "integer overflow" end
    return value
end
function V.new(code, owners, starts, global_size, inputs)
    local result = setmetatable({ code = code, owners = owners, starts = starts, inputs = inputs,
        globals = {}, stack = {}, frames = {}, read_position = 1, pc = 0, executed = 0,
        counts = {}, calls = {}, pairs = {}, max_stack = 0, max_depth = 0, output = {} }, V)
    for i = 1, global_size do result.globals[i] = 0 end
    for i = 1, #code do result.counts[i] = 0 end
    return result
end
function V:step()
    local instruction = self.code[self.pc + 1]
    local op, args, stack = instruction.op, instruction.args, self.stack
    local next_pc = self.pc + 1
    if op == "PUSH" then stack[#stack + 1] = args[1]
    elseif op == "POP" then table.remove(stack)
    elseif op == "LOADG" then stack[#stack + 1] = self.globals[args[1] + 1]
    elseif op == "STOREG" then self.globals[args[1] + 1] = table.remove(stack)
    elseif op == "LOADL" then stack[#stack + 1] = self.frames[#self.frames].locals[args[1] + 1]
    elseif op == "STOREL" then self.frames[#self.frames].locals[args[1] + 1] = table.remove(stack)
    elseif op == "LOADA" or op == "STOREA" then
        local value
        if op == "STOREA" then value = table.remove(stack) end
        local index = table.remove(stack)
        if index < 0 or index >= args[2] then return nil, string.format("index %d out of bounds for array of size %d", index, args[2]) end
        if op == "LOADA" then stack[#stack + 1] = self.globals[args[1] + index + 1]
        else self.globals[args[1] + index + 1] = value end
    elseif V.binary[op] then
        local b, a = table.remove(stack), table.remove(stack)
        local value, err = V.calculate(op, a, b)
        if err then return nil, err end
        stack[#stack + 1] = value
    elseif op == "NEG" or op == "NOT" then
        local value, err = V.calculate(op, table.remove(stack))
        if err then return nil, err end
        stack[#stack + 1] = value
    elseif op == "JUMP" then next_pc = args[1]
    elseif op == "JUMPF" or op == "JUMPT" then
        local value = table.remove(stack)
        if (value == 0) == (op == "JUMPF") then next_pc = args[1] end
    elseif op == "CALL" then
        if #self.frames == 100 then return nil, "call depth limit exceeded" end
        local values, count = {}, args[2]
        for i = count, 1, -1 do values[i] = table.remove(stack) end
        self.frames[#self.frames + 1] = { locals = values, return_address = next_pc }
        local callee, caller = self.starts[args[1]], self.owners[self.pc + 1]
        self.calls[callee] = (self.calls[callee] or 0) + 1
        if not self.pairs[caller] then self.pairs[caller] = {} end
        self.pairs[caller][callee] = (self.pairs[caller][callee] or 0) + 1
        next_pc = args[1]
    elseif op == "ENTER" then
        local area = self.frames[#self.frames].locals
        for i = #area + 1, args[1] do area[i] = 0 end
    elseif op == "RET" or op == "RETV" then next_pc = table.remove(self.frames).return_address
    elseif op == "READ" then
        if self.read_position > #self.inputs then return nil, "read past end of input" end
        stack[#stack + 1], self.read_position = self.inputs[self.read_position], self.read_position + 1
    elseif op == "PRINT" then
        local values = {}
        for i = args[1], 1, -1 do values[i] = tostring(table.remove(stack)) end
        self.output[#self.output + 1] = table.concat(values, " ")
    end
    self.max_stack, self.max_depth = math.max(self.max_stack, #stack), math.max(self.max_depth, #self.frames)
    self.pc = next_pc
    return op ~= "HALT"
end
function V:run()
    while true do
        if self.executed == 100000 then
            self.error, self.error_pc = "instruction limit exceeded", self.pc
            break
        end
        self.executed = self.executed + 1
        self.counts[self.pc + 1] = self.counts[self.pc + 1] + 1
        local more, err = self:step()
        if err then self.error, self.error_pc = err, self.pc; break end
        if not more then break end
    end
    return self
end
return V
