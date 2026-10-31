local function contains(value, ...)
    for _, item in ipairs({...}) do
        if value == item then
            return true
        end
    end
    return false
end
local function fail(token, format, ...)
    error({line = token.line, reason = string.format(format, ...)}, 0)
end
local primitives = {}
local groups = {
    {"FD FORWARD", "FD", "E"},
    {"BK BACK", "BK", "E"},
    {"RT RIGHT", "RT", "E"},
    {"LT LEFT", "LT", "E"},
    {"SETH SETHEADING", "SETH", "E"},
    {"PU PENUP", "PU", ""},
    {"PD PENDOWN", "PD", ""},
    {"PE PENERASE", "PE", ""},
    {"SETPEN", "SETPEN", "E"},
    {"SETXY", "SETXY", "EE"},
    {"SETX", "SETX", "E"},
    {"SETY", "SETY", "E"},
    {"HOME", "HOME", ""},
    {"CS CLEARSCREEN", "CS", ""},
    {"CLEAN", "CLEAN", ""},
    {"FILL", "FILL", ""},
    {"LABEL", "LABEL", "P"},
    {"SNAPSHOT", "SNAPSHOT", ""},
    {"REPEAT", "REPEAT", "EL"},
    {"FOR", "FOR", "QEEL"},
    {"WHILE", "WHILE", "EL"},
    {"IF", "IF", "EL"},
    {"IFELSE", "IFELSE", "ELL"},
    {"TEST", "TEST", "E"},
    {"IFTRUE IFT", "IFTRUE", "L"},
    {"IFFALSE IFF", "IFFALSE", "L"},
    {"STOP", "STOP", ""},
    {"OUTPUT OP", "OUTPUT", "E"},
    {"MAKE", "MAKE", "QE"},
    {"LOCAL", "LOCAL", "Q"},
    {"LOCALMAKE", "LOCALMAKE", "QE"},
    {"TRACE", "TRACE", "Q"},
    {"UNTRACE", "UNTRACE", "Q"},
    {"SEED", "SEED", "E"},
    {"PRINT PR", "PRINT", "P"},
    {"XCOR", "XCOR", "", true},
    {"YCOR", "YCOR", "", true},
    {"HEADING", "HEADING", "", true},
    {"REPCOUNT", "REPCOUNT", "", true},
    {"RANDOM", "RANDOM", "E", true},
    {"ABS", "ABS", "E", true},
    {"NOT", "NOT", "E", true},
    {"AND", "AND", "EE", true},
    {"OR", "OR", "EE", true},
    {"MAX", "MAX", "EE", true},
    {"MIN", "MIN", "EE", true},
    {"TO", "TO", ""},
    {"END", "END", ""},
    {"MOD", "MOD", ""}
}
for _, group in ipairs(groups) do
    for name in group[1]:gmatch("[^ ]+") do
        primitives[name] = {canonical = group[2], inputs = group[3], func = group[4] or false}
    end
end
local function isName(s)
    return s:match("^[A-Z][A-Z0-9_]*$") ~= nil
end
local function numeric(s)
    return s:match("^[0-9]+$") ~= nil
end
local function lex(line)
    local text = line.text:gsub(";.*$", ""):upper()
    local result, i = {}, 1
    while i <= #text do
        if text:sub(i, i) == " " then
            i = i + 1
        else
            local start, token = i, {line = line.number, kind = "symbol"}
            local c = text:sub(i, i)
            if ("[]()+*/="):find(c, 1, true) then
                i = i + 1
            elseif c == "<" or c == ">" then
                i = i + 1
                local next = text:sub(i, i)
                if next == "=" or c == "<" and next == ">" then
                    i = i + 1
                end
            elseif c == "-" then
                token.sign =
                    (i == 1 or (" [("):find(text:sub(i - 1, i - 1), 1, true) ~= nil) and i < #text and
                    text:sub(i + 1, i + 1) ~= " "
                i = i + 1
            else
                while i <= #text and not (" []()+-*/=<>"):find(text:sub(i, i), 1, true) do
                    i = i + 1
                end
                local word = text:sub(start, i - 1)
                if numeric(word) then
                    token.kind, token.value = "number", tonumber(word)
                elseif word:sub(1, 1) == ":" and isName(word:sub(2)) then
                    token.kind, token.name = "variable", word:sub(2)
                elseif word:sub(1, 1) == '"' and isName(word:sub(2)) then
                    token.kind, token.name = "quoted", word:sub(2)
                elseif isName(word) then
                    token.kind, token.name = "word", word
                else
                    fail(token, "bad token '%s'", word)
                end
            end
            token.text = text:sub(start, i - 1)
            result[#result + 1] = token
        end
    end
    return result
end
local Parser = {}
Parser.__index = Parser
function Parser:peek()
    return self.tokens[self.position]
end
function Parser:take()
    local token = self:peek()
    self.position = self.position + 1
    return token
end
function Parser:unknown(token)
    return token.kind == "word" and not primitives[token.text] and not self.procedures[token.text]
end
function Parser:check(owner)
    local next = self:peek()
    if not next or next.text == "]" or next.text == ")" then
        fail(owner, "not enough inputs to %s", owner.text)
    end
    if self:unknown(next) then
        fail(next, "I don't know how to %s", next.text)
    end
    return next
end
function Parser:input(kind, owner)
    local next = self:check(owner)
    if kind == "L" then
        if next.text ~= "[" then
            fail(next, "%s doesn't like %s as input", owner.text, next.text)
        end
        local opening, commands = self:take(), {}
        while true do
            local token = self:peek()
            if not token then
                fail(opening, "missing ]")
            end
            if token.text == "]" then
                self:take()
                break
            end
            commands[#commands + 1] = self:command()
        end
        return {list = commands}
    elseif kind == "Q" or kind == "P" and next.kind == "quoted" then
        if next.kind ~= "quoted" then
            fail(next, "%s doesn't like %s as input", owner.text, next.text)
        end
        return {quoted = self:take()}
    end
    return {expression = self:comparison(owner)}
end
function Parser:term(owner)
    local token = self:check(owner)
    self:take()
    local result = {token = token, args = {}}
    if token.kind == "number" then
        result.kind = "number"
    elseif token.kind == "variable" then
        result.kind = "variable"
    elseif token.text == "-" then
        result.kind, result.args = "unary", {self:term(token)}
    elseif token.text == "(" then
        local value = self:comparison(token)
        if not self:peek() or self:peek().text ~= ")" then
            fail(token, "missing )")
        end
        self:take()
        return value
    else
        local primitive, procedure = primitives[token.text], self.procedures[token.text]
        if primitive and primitive.func then
            result.kind = "function"
            for _ = 1, #primitive.inputs do
                result.args[#result.args + 1] = self:input("E", token).expression
            end
        elseif token.kind == "word" and procedure then
            result.kind = "procedure"
            for _ = 1, #procedure.parameters do
                result.args[#result.args + 1] = self:input("E", token).expression
            end
        else
            fail(token, "%s doesn't like %s as input", owner.text, token.text)
        end
    end
    return result
end
function Parser:product(owner)
    local result = self:term(owner)
    while self:peek() and contains(self:peek().text, "*", "/", "MOD") do
        local op = self:take()
        result = {kind = "binary", token = op, args = {result, self:term(op)}}
    end
    return result
end
function Parser:sum(owner)
    local result = self:product(owner)
    while self:peek() and
        (self:peek().text == "+" or self:peek().text == "-" and not self:peek().sign) do
        local op = self:take()
        result = {kind = "binary", token = op, args = {result, self:product(op)}}
    end
    return result
end
function Parser:comparison(owner)
    local result = self:sum(owner)
    while self:peek() and contains(self:peek().text, "=", "<>", "<", ">", "<=", ">=") do
        local op = self:take()
        result = {kind = "binary", token = op, args = {result, self:sum(op)}}
    end
    return result
end
function Parser:command()
    local token = self:take()
    if token.text == "]" then
        fail(token, "unexpected ]")
    end
    if
        token.text == "(" and self:peek() and self:peek().kind == "word" and
            contains(self:peek().text, "PRINT", "PR")
     then
        local owner = self:take()
        local result = {kind = "multiple", token = owner, inputs = {}}
        while true do
            local next = self:peek()
            if not next or next.text == "]" then
                fail(token, "missing )")
            end
            if next.text == ")" then
                self:take()
                return result
            end
            result.inputs[#result.inputs + 1] = self:input("P", owner)
        end
    end
    if token.kind == "word" and contains(token.text, "TO", "END") then
        fail(token, "misplaced %s", token.text)
    end
    local result = {token = token, inputs = {}}
    local primitive, procedure = primitives[token.text], self.procedures[token.text]
    if token.kind == "word" and primitive and not primitive.func and primitive.canonical ~= "MOD" then
        result.kind = primitive.canonical
        if not self.inside and contains(result.kind, "STOP", "OUTPUT", "LOCAL", "LOCALMAKE") then
            fail(token, "can only use %s inside a procedure", token.text)
        end
        for i = 1, #primitive.inputs do
            result.inputs[#result.inputs + 1] = self:input(primitive.inputs:sub(i, i), token)
        end
        if
            contains(result.kind, "TRACE", "UNTRACE") and
                not self.procedures[result.inputs[1].quoted.name]
         then
            fail(result.inputs[1].quoted, "I don't know how to %s", result.inputs[1].quoted.name)
        end
    elseif token.kind == "word" and procedure then
        result.kind = "procedure"
        for _ = 1, #procedure.parameters do
            result.inputs[#result.inputs + 1] = self:input("E", token)
        end
    elseif self:unknown(token) then
        fail(token, "I don't know how to %s", token.text)
    else
        fail(token, "you don't say what to do with %s", token.text)
    end
    return result
end
function Parser:sequence()
    local result = {}
    while self:peek() do
        result[#result + 1] = self:command()
    end
    return result
end
local function parser(tokens, procedures, inside)
    return setmetatable(
        {tokens = tokens, procedures = procedures, inside = inside, position = 1},
        Parser
    )
end
local function trunc(a, b)
    local value = math.abs(a) // math.abs(b)
    return (a < 0) ~= (b < 0) and -value or value
end
local function truth(value)
    return value and 1 or 0
end
local function key(x, y)
    return x .. ":" .. y
end
local directions = {{0, 1}, {1, 1}, {1, 0}, {1, -1}, {0, -1}, {-1, -1}, {-1, 0}, {-1, 1}}
local Runtime = {}
Runtime.__index = Runtime
function Runtime:emit(format, ...)
    self.output[#self.output + 1] = string.format(format, ...)
end
function Runtime:current()
    return self.environments[#self.environments]
end
function Runtime:assign(name, value)
    for i = #self.environments, 2, -1 do
        if self.environments[i].variables[name] ~= nil then
            self.environments[i].variables[name] = value
            return
        end
    end
    self.environments[1].variables[name] = value
end
function Runtime:evaluate(expression)
    local token = expression.token
    if expression.kind == "number" then
        return token.value
    elseif expression.kind == "variable" then
        for i = #self.environments, 1, -1 do
            local value = self.environments[i].variables[token.name]
            if value ~= nil then
                return value
            end
        end
        fail(token, "%s has no value", token.name)
    elseif expression.kind == "unary" then
        return -self:evaluate(expression.args[1])
    end
    local values = {}
    for i, argument in ipairs(expression.args) do
        values[i] = self:evaluate(argument)
    end
    if expression.kind == "procedure" then
        local value = self:call(token, values)
        if value == nil then
            fail(token, "%s did not output", token.text)
        end
        return value
    elseif expression.kind == "binary" then
        local a, b = values[1], values[2]
        if token.text == "+" then
            return a + b
        elseif token.text == "-" then
            return a - b
        elseif token.text == "*" then
            return a * b
        elseif token.text == "/" or token.text == "MOD" then
            if b == 0 then
                fail(token, "%s doesn't like 0 as input", token.text)
            end
            local q = trunc(a, b)
            return token.text == "/" and q or a - b * q
        elseif token.text == "=" then
            return truth(a == b)
        elseif token.text == "<>" then
            return truth(a ~= b)
        elseif token.text == "<" then
            return truth(a < b)
        elseif token.text == ">" then
            return truth(a > b)
        elseif token.text == "<=" then
            return truth(a <= b)
        else
            return truth(a >= b)
        end
    end
    if token.text == "XCOR" then
        return self.x
    elseif token.text == "YCOR" then
        return self.y
    elseif token.text == "HEADING" then
        return self.heading
    elseif token.text == "REPCOUNT" then
        if #self.repetitions == 0 then
            fail(token, "REPCOUNT outside REPEAT")
        end
        return self.repetitions[#self.repetitions]
    elseif token.text == "RANDOM" then
        if values[1] < 1 then
            fail(token, "RANDOM doesn't like %d as input", values[1])
        end
        self.random = 48271 * self.random % 2147483647
        return self.random % values[1]
    elseif token.text == "ABS" then
        return math.abs(values[1])
    elseif token.text == "NOT" then
        return truth(values[1] == 0)
    elseif token.text == "AND" then
        return truth(values[1] ~= 0 and values[2] ~= 0)
    elseif token.text == "OR" then
        return truth(values[1] ~= 0 or values[2] ~= 0)
    elseif token.text == "MAX" then
        return math.max(values[1], values[2])
    else
        return math.min(values[1], values[2])
    end
end
function Runtime:call(token, values)
    if #self.calls == 100 then
        fail(token, "recursion too deep")
    end
    local procedure = self.procedures[token.text]
    local traced, indent = self.traced[procedure.name], string.rep(" ", 2 * #self.calls)
    if traced then
        local parts = {procedure.name}
        for _, value in ipairs(values) do
            parts[#parts + 1] = tostring(value)
        end
        self:emit("%s( %s )", indent, table.concat(parts, " "))
    end
    local environment = {variables = {}}
    for i, name in ipairs(procedure.parameters) do
        environment.variables[name] = values[i]
    end
    self.environments[#self.environments + 1], self.calls[#self.calls + 1] =
        environment,
        procedure.name
    local signal = self:sequence(procedure.body)
    self.environments[#self.environments], self.calls[#self.calls] = nil, nil
    if traced then
        if signal and signal.output then
            self:emit("%s%s outputs %d", indent, procedure.name, signal.value)
        else
            self:emit("%s%s stops", indent, procedure.name)
        end
    end
    return signal and signal.output and signal.value or nil
end
function Runtime:mark(x, y, character)
    self.canvas[key(x, y)] = {x = x, y = y, character = character}
end
function Runtime:apply(x, y)
    if self.pen == "DOWN" then
        self:mark(x, y, self.character)
    elseif self.pen == "ERASE" then
        self.canvas[key(x, y)] = nil
    end
end
function Runtime:forward(steps)
    local delta = directions[self.heading // 45 + 1]
    local dx, dy = delta[1], delta[2]
    if steps < 0 then
        steps, dx, dy = -steps, -dx, -dy
    end
    self:apply(self.x, self.y)
    for _ = 1, steps do
        self.x, self.y = self.x + dx, self.y + dy
        self:apply(self.x, self.y)
    end
end
function Runtime:move(x, y)
    local x0, y0, dx, dy = self.x, self.y, x - self.x, y - self.y
    local steps = math.max(math.abs(dx), math.abs(dy))
    if steps == 0 then
        self:apply(x0, y0)
    else
        for i = 0, steps do
            self:apply(
                x0 + (2 * i * dx + steps) // (2 * steps),
                y0 + (2 * i * dy + steps) // (2 * steps)
            )
        end
    end
    self.x, self.y = x, y
end
function Runtime:bounds()
    local x1, y1, x2, y2, count
    count = 0
    for _, cell in pairs(self.canvas) do
        if count == 0 then
            x1, y1, x2, y2 = cell.x, cell.y, cell.x, cell.y
        end
        x1, y1, x2, y2 =
            math.min(x1, cell.x),
            math.min(y1, cell.y),
            math.max(x2, cell.x),
            math.max(y2, cell.y)
        count = count + 1
    end
    return x1, y1, x2, y2, count
end
function Runtime:fill()
    if not next(self.canvas) or self.canvas[key(self.x, self.y)] then
        return
    end
    local x1, y1, x2, y2 = self:bounds()
    if self.x < x1 or self.x > x2 or self.y < y1 or self.y > y2 then
        return
    end
    local queue, i = {{self.x, self.y}}, 1
    self:mark(self.x, self.y, self.character)
    while i <= #queue do
        local x, y = queue[i][1], queue[i][2]
        i = i + 1
        for _, delta in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
            local a, b = x + delta[1], y + delta[2]
            if a >= x1 and a <= x2 and b >= y1 and b <= y2 and not self.canvas[key(a, b)] then
                self:mark(a, b, self.character)
                queue[#queue + 1] = {a, b}
            end
        end
    end
end
function Runtime:picture()
    if not next(self.canvas) then
        self:emit("CANVAS 0 0 0")
        return
    end
    local x1, y1, x2, y2, count = self:bounds()
    self:emit("CANVAS %d %d %d", x2 - x1 + 1, y2 - y1 + 1, count)
    for y = y2, y1, -1 do
        local row = {}
        for x = x1, x2 do
            local cell = self.canvas[key(x, y)]
            row[#row + 1] = cell and cell.character or " "
        end
        self:emit("%s", (table.concat(row):gsub(" +$", "")))
    end
end
function Runtime:item(input)
    return input.quoted and input.quoted.name or tostring(self:evaluate(input.expression))
end
function Runtime:sequence(commands)
    for _, command in ipairs(commands) do
        local signal = self:execute(command)
        if signal then
            return signal
        end
    end
    return nil
end
function Runtime:execute(command)
    if command.kind == "multiple" then
        local parts = {}
        for _, input in ipairs(command.inputs) do
            parts[#parts + 1] = self:item(input)
        end
        self:emit("%s", table.concat(parts, " "))
        return nil
    elseif command.kind == "WHILE" then
        while self:evaluate(command.inputs[1].expression) ~= 0 do
            local signal = self:sequence(command.inputs[2].list)
            if signal then
                return signal
            end
        end
        return nil
    end
    local values, token = {}, command.token
    for i, input in ipairs(command.inputs) do
        values[i] = input.expression and self:evaluate(input.expression) or 0
    end
    if command.kind == "procedure" then
        local value = self:call(token, values)
        if value ~= nil then
            fail(token, "you don't say what to do with %d", value)
        end
        return nil
    end
    local kind = command.kind
    if kind == "FD" then
        self:forward(values[1])
    elseif kind == "BK" then
        self:forward(-values[1])
    elseif kind == "RT" or kind == "LT" or kind == "SETH" then
        local angle = values[1]
        if angle % 45 ~= 0 then
            fail(token, "%s doesn't like %d as input", token.text, angle)
        end
        if kind == "RT" then
            angle = self.heading + angle
        elseif kind == "LT" then
            angle = self.heading - angle
        end
        self.heading = angle % 360
    elseif kind == "PU" then
        self.pen = "UP"
    elseif kind == "PD" then
        self.pen = "DOWN"
    elseif kind == "PE" then
        self.pen = "ERASE"
    elseif kind == "SETPEN" then
        if values[1] < 33 or values[1] > 126 then
            fail(token, "SETPEN doesn't like %d as input", values[1])
        end
        self.character = string.char(values[1])
    elseif kind == "SETXY" then
        self:move(values[1], values[2])
    elseif kind == "SETX" then
        self:move(values[1], self.y)
    elseif kind == "SETY" then
        self:move(self.x, values[1])
    elseif kind == "HOME" then
        self:move(0, 0)
        self.heading = 0
    elseif kind == "CS" then
        self.canvas, self.x, self.y, self.heading = {}, 0, 0, 0
    elseif kind == "CLEAN" then
        self.canvas = {}
    elseif kind == "FILL" then
        self:fill()
    elseif kind == "LABEL" then
        local text =
            command.inputs[1].quoted and command.inputs[1].quoted.name or tostring(values[1])
        local delta = directions[self.heading // 45 + 1]
        for i = 1, #text do
            self:mark(self.x + (i - 1) * delta[1], self.y + (i - 1) * delta[2], text:sub(i, i))
        end
    elseif kind == "SNAPSHOT" then
        self:picture()
    elseif kind == "REPEAT" then
        if #command.inputs[2].list == 0 then
            return
        end
        for n = 1, values[1] do
            self.repetitions[#self.repetitions + 1] = n
            local signal = self:sequence(command.inputs[2].list)
            self.repetitions[#self.repetitions] = nil
            if signal then
                return signal
            end
        end
    elseif kind == "FOR" then
        if #command.inputs[4].list == 0 then
            self:assign(command.inputs[1].quoted.name, values[3])
            return
        end
        local a, b = values[2], values[3]
        for value = a, b, a <= b and 1 or -1 do
            self:assign(command.inputs[1].quoted.name, value)
            local signal = self:sequence(command.inputs[4].list)
            if signal then
                return signal
            end
        end
    elseif kind == "IF" then
        if values[1] ~= 0 then
            return self:sequence(command.inputs[2].list)
        end
    elseif kind == "IFELSE" then
        return self:sequence(command.inputs[values[1] ~= 0 and 2 or 3].list)
    elseif kind == "TEST" then
        self:current().test = values[1] ~= 0
    elseif kind == "IFTRUE" or kind == "IFFALSE" then
        local test = self:current().test
        if test == nil then
            fail(token, "%s without TEST", token.text)
        end
        if test == (kind == "IFTRUE") then
            return self:sequence(command.inputs[1].list)
        end
    elseif kind == "STOP" then
        return {output = false}
    elseif kind == "OUTPUT" then
        return {output = true, value = values[1]}
    elseif kind == "MAKE" then
        self:assign(command.inputs[1].quoted.name, values[2])
    elseif kind == "LOCAL" then
        self:current().variables[command.inputs[1].quoted.name] = 0
    elseif kind == "LOCALMAKE" then
        self:current().variables[command.inputs[1].quoted.name] = values[2]
    elseif kind == "TRACE" then
        self.traced[command.inputs[1].quoted.name] = true
    elseif kind == "UNTRACE" then
        self.traced[command.inputs[1].quoted.name] = nil
    elseif kind == "SEED" then
        if values[1] < 1 then
            fail(token, "SEED doesn't like %d as input", values[1])
        end
        self.random = values[1]
    elseif kind == "PRINT" then
        self:emit(
            "%s",
            command.inputs[1].quoted and command.inputs[1].quoted.name or tostring(values[1])
        )
    end
    return nil
end
local output = {}
local function runProgram(name, lines)
    output[#output + 1] = "PROGRAM " .. name
    local machine, executing
    local ok, caught =
        pcall(
        function()
            local procedures, ordered, top, current = {}, {}, {}, nil
            for _, line in ipairs(lines) do
                local tokens = lex(line)
                if #tokens > 0 then
                    local first = tokens[1]
                    if first.kind == "word" and first.text == "TO" then
                        if current then
                            fail(first, "TO inside definition of %s", current.name)
                        end
                        if not tokens[2] or tokens[2].kind ~= "word" then
                            fail(first, "bad procedure header")
                        end
                        local procedureName = tokens[2].text
                        if primitives[procedureName] then
                            fail(first, "%s is a primitive", procedureName)
                        end
                        if procedures[procedureName] then
                            fail(first, "%s is already defined", procedureName)
                        end
                        local parameters, seen = {}, {}
                        for i = 3, #tokens do
                            local token = tokens[i]
                            if token.kind ~= "variable" then
                                fail(first, "bad procedure header")
                            end
                            if seen[token.name] then
                                fail(first, "duplicate input %s", token.text)
                            end
                            seen[token.name] = true
                            parameters[#parameters + 1] = token.name
                        end
                        current = {
                            name = procedureName,
                            line = first.line,
                            parameters = parameters,
                            tokens = {}
                        }
                        procedures[procedureName], ordered[#ordered + 1] = current, current
                    elseif #tokens == 1 and first.kind == "word" and first.text == "END" then
                        if not current then
                            fail(first, "END without TO")
                        end
                        current = nil
                    else
                        local target = current and current.tokens or top
                        for _, token in ipairs(tokens) do
                            target[#target + 1] = token
                        end
                    end
                end
            end
            if current then
                fail({line = current.line}, "missing END for %s", current.name)
            end
            for _, procedure in ipairs(ordered) do
                procedure.body = parser(procedure.tokens, procedures, true):sequence()
            end
            local commands = parser(top, procedures, false):sequence()
            machine =
                setmetatable(
                {
                    procedures = procedures,
                    environments = {{variables = {}}},
                    calls = {},
                    repetitions = {},
                    traced = {},
                    canvas = {},
                    x = 0,
                    y = 0,
                    heading = 0,
                    pen = "DOWN",
                    character = "*",
                    random = 1,
                    output = output
                },
                Runtime
            )
            executing = true
            machine:sequence(commands)
            machine:emit(
                "TURTLE %d %d %d %s %s",
                machine.x,
                machine.y,
                machine.heading,
                machine.pen,
                machine.character
            )
            machine:picture()
        end
    )
    if not ok then
        output[#output + 1] = string.format("ERROR line %d: %s", caught.line, caught.reason)
        if executing then
            local i = #machine.calls
            while i >= 1 do
                local procedureName, count = machine.calls[i], 1
                i = i - 1
                while i >= 1 and machine.calls[i] == procedureName do
                    count, i = count + 1, i - 1
                end
                output[#output + 1] =
                    "  in " .. procedureName .. (count > 1 and " x" .. count or "")
            end
        end
    end
end
local name, lines, lineNumber = nil, {}, 0
for line in io.lines() do
    lineNumber = lineNumber + 1
    if line == "#EOF" then
        runProgram(name, lines)
        break
    elseif line:sub(1, 9) == "#PROGRAM " then
        if name then
            runProgram(name, lines)
        end
        name, lines = line:sub(10), {}
    else
        lines[#lines + 1] = {text = line, number = lineNumber}
    end
end
if #output > 0 then
    io.write(table.concat(output, "\n"), "\n")
end
