local signatures = {
    ABS = {'I'}, SGN = {'I'}, INT = {'I'}, SQR = {'I'}, RND = {'I'},
    LEN = {'S'}, ASC = {'S'}, VAL = {'S'}, ['CHR$'] = {'I'}, ['STR$'] = {'I'},
    ['LEFT$'] = {'SI'}, ['RIGHT$'] = {'SI'}, ['MID$'] = {'SI','SII'}, INSTR = {'SS'}
}

local error_codes = {
    ['NEXT WITHOUT FOR'] = 1, ['RETURN WITHOUT GOSUB'] = 3,
    ['OUT OF DATA'] = 4, ['ILLEGAL FUNCTION CALL'] = 5, OVERFLOW = 6,
    ['OUT OF MEMORY'] = 7, ['UNDEFINED LINE NUMBER'] = 8,
    ['SUBSCRIPT OUT OF RANGE'] = 9, ['DUPLICATE DEFINITION'] = 10,
    ['DIVISION BY ZERO'] = 11, ['TYPE MISMATCH'] = 13,
    ['STRING TOO LONG'] = 15, ['RESUME WITHOUT ERROR'] = 20,
    ['FOR WITHOUT NEXT'] = 26, ['WHILE WITHOUT WEND'] = 29,
    ['WEND WITHOUT WHILE'] = 30, ['INPUT PAST END'] = 62
}

local operators = {
    [0] = {OR = true},
    [1] = {AND = true},
    [2] = {},
    [3] = {['='] = true, ['<>'] = true, ['<'] = true,
           ['>'] = true, ['<='] = true, ['>='] = true},
    [4] = {['+'] = true, ['-'] = true},
    [5] = {['*'] = true, ['/'] = true, MOD = true},
    [6] = {},
    [7] = {['^'] = true}
}

local comparisons = operators[3]

local function syntax()
    error({kind = 'syntax'}, 0)
end

local function fault(message)
    error({kind = 'runtime', message = message}, 0)
end

local function variable(name)
    return name:match('^[A-Z][0-9]?%$?$') ~= nil
end

local function name_type(name)
    return name:sub(-1) == '$' and 'S' or 'I'
end

local function value_type(value)
    return type(value) == 'string' and 'S' or 'I'
end

local function expression_node(kind, value_type_, value, args)
    return {kind = kind, type = value_type_, value = value, args = args or {}}
end

local function statement(kind)
    return {
        kind = kind, line = 0, next = nil, expr = nil, target = nil,
        targets = {}, expressions = {}, values = {}, numbers = {},
        name = '', mode = '', clauses = {}, items = {}
    }
end

local function tokenize(text)
    local tokens = {}
    local p = 1
    while p <= #text do
        local ch = text:sub(p, p)
        if ch == ' ' then
            p = p + 1
        elseif ch == '"' then
            local ending = text:find('"', p + 1, true)
            if not ending then syntax() end
            tokens[#tokens + 1] = {
                kind = 'S', text = text:sub(p, ending),
                value = text:sub(p + 1, ending - 1)
            }
            p = ending + 1
        elseif ch:match('%d') then
            local start = p
            repeat
                p = p + 1
            until p > #text or not text:sub(p, p):match('%d')
            local word = text:sub(start, p - 1)
            local n = tonumber(word)
            if n > 32767 then syntax() end
            tokens[#tokens + 1] = {kind = 'I', text = word, value = n}
        elseif ch:match('[A-Z]') then
            if text:sub(p, p + 2) == 'REM' then
                tokens[#tokens + 1] = {kind = 'W', text = 'REM', value = 'REM'}
                break
            end
            local start = p
            repeat
                p = p + 1
            until p > #text or not text:sub(p, p):match('[A-Z0-9]')
            if text:sub(p, p) == '$' then p = p + 1 end
            local word = text:sub(start, p - 1)
            tokens[#tokens + 1] = {kind = 'W', text = word, value = word}
        else
            if not ch:match('[+%-%*/%^=<>() ,;:]') then syntax() end
            local word = text:sub(p, p + 1)
            if word ~= '<>' and word ~= '<=' and word ~= '>=' then
                word = ch
            end
            tokens[#tokens + 1] = {kind = 'P', text = word, value = word}
            p = p + #word
        end
    end
    tokens[#tokens + 1] = {kind = 'E', text = '', value = ''}
    return tokens
end

local Parser = {}
Parser.__index = Parser

function Parser.new(tokens)
    return setmetatable({tokens = tokens, position = 1}, Parser)
end

function Parser:current()
    return self.tokens[self.position]
end

function Parser:at(word)
    local current = self:current()
    return (current.kind == 'P' or current.kind == 'W') and current.text == word
end

function Parser:take(word)
    if not self:at(word) then return false end
    self.position = self.position + 1
    return true
end

function Parser:expect(word)
    if not self:take(word) then syntax() end
end

function Parser:integer()
    local e = self:expression(0)
    if e.type ~= 'I' then syntax() end
    return e
end

function Parser:integer_at(level)
    local e = self:expression(level)
    if e.type ~= 'I' then syntax() end
    return e
end

function Parser:number()
    local token = self:current()
    if token.kind ~= 'I' then syntax() end
    self.position = self.position + 1
    return token.value
end

function Parser:target()
    local token = self:current()
    if token.kind ~= 'W' or not variable(token.text) then syntax() end
    self.position = self.position + 1
    local args = {}
    if self:take('(') then
        args[#args + 1] = self:integer()
        if self:take(',') then args[#args + 1] = self:integer() end
        self:expect(')')
    end
    return expression_node(#args == 0 and 'variable' or 'array',
                           name_type(token.text), token.text, args)
end

function Parser:expression(level)
    level = level or 0
    if level == 2 and self:take('NOT') then
        return expression_node('unary', 'I', 'NOT', {self:integer_at(2)})
    end
    if level == 6 and self:take('-') then
        return expression_node('unary', 'I', '-', {self:integer_at(6)})
    end
    if level == 8 then return self:primary() end
    local left = self:expression(level + 1)
    while operators[level][self:current().text] do
        local op = self:current().text
        self.position = self.position + 1
        local right = self:expression(level == 7 and 6 or level + 1)
        if left.type ~= right.type or
           (left.type == 'S' and level ~= 3 and op ~= '+') then
            syntax()
        end
        left = expression_node('binary', level == 3 and 'I' or left.type,
                               op, {left, right})
        if level == 7 then break end
    end
    return left
end

function Parser:primary()
    local token = self:current()
    if token.kind == 'I' or token.kind == 'S' then
        self.position = self.position + 1
        return expression_node('constant', token.kind, token.value)
    end
    if self:take('(') then
        local e = self:expression(0)
        self:expect(')')
        return e
    end
    if token.kind == 'W' and variable(token.text) then
        return self:target()
    end
    if self:take('ERR') then return expression_node('builtin', 'I', 'ERR') end
    if self:take('ERL') then return expression_node('builtin', 'I', 'ERL') end
    if token.kind == 'W' and signatures[token.text] then
        self.position = self.position + 1
        self:expect('(')
        local args = {self:expression(0)}
        while self:take(',') do args[#args + 1] = self:expression(0) end
        self:expect(')')
        local kinds = {}
        for _, e in ipairs(args) do kinds[#kinds + 1] = e.type end
        local signature = table.concat(kinds)
        local valid = false
        for _, allowed in ipairs(signatures[token.text]) do
            if signature == allowed then valid = true end
        end
        if not valid then syntax() end
        return expression_node('call', name_type(token.text), token.text, args)
    end
    syntax()
end

function Parser:clause()
    if self:current().kind == 'I' then
        return {line = self:number(), body = {}}
    end
    return {line = nil, body = self:list(true)}
end

function Parser:list(in_clause)
    local statements = {self:statement(in_clause or false)}
    while self:take(':') do
        statements[#statements + 1] = self:statement(in_clause or false)
    end
    return statements
end

function Parser:statement(in_clause)
    local word = self:current().text
    if in_clause and ({IF = true, FOR = true, NEXT = true,
                       WHILE = true, WEND = true, DATA = true})[word] then
        syntax()
    end
    local s = statement(word)
    for _, name in ipairs({'REM', 'RETURN', 'WEND', 'END', 'STOP'}) do
        if self:take(name) then return s end
    end
    if self:take('PRINT') then
        local expression_last = false
        while self:current().kind ~= 'E' and
              not self:at(':') and not self:at('ELSE') do
            if self:take(';') then
                s.items[#s.items + 1] = {kind = ';'}
                expression_last = false
            elseif self:take(',') then
                s.items[#s.items + 1] = {kind = ','}
                expression_last = false
            else
                local kind = self:at('TAB') and 'TAB' or
                             self:at('SPC') and 'SPC' or 'value'
                if kind == 'value' and expression_last then syntax() end
                local e
                if kind == 'value' then
                    e = self:expression(0)
                else
                    self.position = self.position + 1
                    self:expect('(')
                    e = self:integer()
                    self:expect(')')
                end
                s.items[#s.items + 1] = {kind = kind, expr = e}
                expression_last = kind == 'value'
            end
        end
        return s
    end
    if self:take('INPUT') or self:take('READ') or self:take('DIM') then
        repeat
            local t = self:target()
            if word == 'DIM' and t.kind ~= 'array' then syntax() end
            s.targets[#s.targets + 1] = t
        until not self:take(',')
        return s
    end
    if self:take('DATA') then
        repeat
            local negative = self:take('-')
            local token = self:current()
            if token.kind ~= 'I' and (token.kind ~= 'S' or negative) then
                syntax()
            end
            self.position = self.position + 1
            s.values[#s.values + 1] = negative and -token.value or token.value
        until not self:take(',')
        return s
    end
    if self:take('IF') then
        s.expr = self:integer()
        self:expect('THEN')
        s.clauses[1] = self:clause()
        if self:take('ELSE') then s.clauses[2] = self:clause() end
        if self:current().kind ~= 'E' then syntax() end
        return s
    end
    if self:take('GOTO') or self:take('GOSUB') then
        s.numbers[1] = self:number()
        return s
    end
    if self:take('ON') then
        if self:take('ERROR') then
            s.kind = 'handler'
            self:expect('GOTO')
            s.numbers[1] = self:number()
        else
            s.expr = self:integer()
            if self:take('GOTO') then
                s.mode = 'GOTO'
            else
                self:expect('GOSUB')
                s.mode = 'GOSUB'
            end
            s.numbers[1] = self:number()
            while self:take(',') do s.numbers[#s.numbers + 1] = self:number() end
        end
        return s
    end
    if self:take('RESUME') then
        if self:take('NEXT') then
            s.mode = 'NEXT'
        elseif self:current().kind == 'I' then
            s.mode = 'line'
            s.numbers[1] = self:number()
        end
        return s
    end
    if self:take('FOR') then
        local token = self:current()
        if token.kind ~= 'W' or not variable(token.text) or
           name_type(token.text) ~= 'I' then syntax() end
        s.name = token.text
        self.position = self.position + 1
        self:expect('=')
        s.expressions[1] = self:integer()
        self:expect('TO')
        s.expressions[2] = self:integer()
        if self:take('STEP') then
            s.expressions[3] = self:integer()
        else
            s.expressions[3] = expression_node('constant', 'I', 1)
        end
        return s
    end
    if self:take('NEXT') then
        local token = self:current()
        if token.kind == 'W' and variable(token.text) and
           name_type(token.text) == 'I' then
            s.name = token.text
            self.position = self.position + 1
        end
        return s
    end
    if self:take('WHILE') or self:take('RANDOMIZE') then
        s.expr = self:integer()
        return s
    end
    if self:take('RESTORE') then
        if self:current().kind == 'I' then s.numbers[1] = self:number() end
        return s
    end
    self:take('LET')
    s.kind = 'assign'
    s.target = self:target()
    self:expect('=')
    s.expr = self:expression(0)
    if s.expr.type ~= s.target.type then syntax() end
    return s
end

function Parser:parse()
    local result = self:list(false)
    if self:current().kind ~= 'E' then syntax() end
    return result
end

local Machine = {}
Machine.__index = Machine

function Machine.new(inputs)
    return setmetatable({
        inputs = inputs, variables = {}, arrays = {}, stack = {},
        entries = {}, sequence = {}, data = {}, data_position = 1,
        input_position = 1, random = 1, handler = 0, handling = false,
        remembered = nil, err = 0, erl = 0, buffer = '', output = {}
    }, Machine)
end

function Machine:end_line()
    self.output[#self.output + 1] = (self.buffer:gsub(' +$', ''))
    self.buffer = ''
end

function Machine:message(text)
    if #self.buffer > 0 then self:end_line() end
    self.output[#self.output + 1] = text
end

function Machine:checked(value)
    if value < -32768 or value > 32767 then fault('OVERFLOW') end
    return math.tointeger(value) or value
end

function Machine:get(name)
    if self.variables[name] ~= nil then return self.variables[name] end
    return name_type(name) == 'S' and '' or 0
end

function Machine:declare(name, bounds)
    local values = {}
    local count = 1
    for _, bound in ipairs(bounds) do count = count * (bound + 1) end
    local default = name_type(name) == 'S' and '' or 0
    for i = 1, count do values[i] = default end
    self.arrays[name] = {bounds = bounds, values = values}
end

function Machine:address(target)
    local name = target.value
    if target.kind == 'variable' then return {name = name} end
    local indices = {}
    for _, e in ipairs(target.args) do
        indices[#indices + 1] = self:evaluate(e)
    end
    if not self.arrays[name] then
        local bounds = {}
        for i = 1, #indices do bounds[i] = 10 end
        self:declare(name, bounds)
    end
    local array = self.arrays[name]
    if #indices ~= #array.bounds then fault('SUBSCRIPT OUT OF RANGE') end
    local index = 0
    for i, value in ipairs(indices) do
        if value < 0 or value > array.bounds[i] then fault('SUBSCRIPT OUT OF RANGE') end
        index = index * (array.bounds[i] + 1) + value
    end
    return {name = name, index = index + 1}
end

function Machine:load(address)
    if not address.index then return self:get(address.name) end
    return self.arrays[address.name].values[address.index]
end

function Machine:store(address, value)
    if not address.index then
        self.variables[address.name] = value
    else
        self.arrays[address.name].values[address.index] = value
    end
end

local function quotient(a, b)
    local result = math.abs(a) // math.abs(b)
    return ((a < 0) ~= (b < 0)) and -result or result
end

function Machine:evaluate(e)
    local op = e.value
    if e.kind == 'constant' then return op end
    if e.kind == 'variable' or e.kind == 'array' then
        return self:load(self:address(e))
    end
    if e.kind == 'builtin' then return op == 'ERR' and self.err or self.erl end
    if e.kind == 'unary' then
        local a = self:evaluate(e.args[1])
        if op == 'NOT' then return ~a end
        return self:checked(-a)
    end
    local args = {}
    for _, a in ipairs(e.args) do args[#args + 1] = self:evaluate(a) end
    if e.kind == 'call' then return self:call(op, args) end
    local a, b = args[1], args[2]
    if comparisons[op] then
        local success
        if op == '=' then success = a == b
        elseif op == '<>' then success = a ~= b
        elseif op == '<' then success = a < b
        elseif op == '>' then success = a > b
        elseif op == '<=' then success = a <= b
        else success = a >= b end
        return success and -1 or 0
    end
    if e.type == 'S' then
        local text = a .. b
        if #text > 255 then fault('STRING TOO LONG') end
        return text
    end
    if op == '+' then return self:checked(a + b) end
    if op == '-' then return self:checked(a - b) end
    if op == '*' then return self:checked(a * b) end
    if op == '/' or op == 'MOD' then
        if b == 0 then fault('DIVISION BY ZERO') end
        local q = quotient(a, b)
        if op == '/' then return self:checked(q) end
        return a - b * q
    end
    if op == '^' then
        if b < 0 then fault('ILLEGAL FUNCTION CALL') end
        if math.abs(a) > 1 and b > 15 then fault('OVERFLOW') end
        return self:checked(a ^ b)
    end
    if op == 'AND' then return a & b end
    if op == 'OR' then return a | b end
    syntax()
end

function Machine:call(name, args)
    local a, b, c = args[1], args[2], args[3]
    if name == 'ABS' then return self:checked(math.abs(a)) end
    if name == 'SGN' then return a < 0 and -1 or a > 0 and 1 or 0 end
    if name == 'INT' then return a end
    if name == 'SQR' then
        if a < 0 then fault('ILLEGAL FUNCTION CALL') end
        return math.floor(math.sqrt(a))
    end
    if name == 'RND' then
        if a < 1 then fault('ILLEGAL FUNCTION CALL') end
        self.random = (48271 * self.random) % 2147483647
        return self.random % a + 1
    end
    if name == 'LEN' then return #a end
    if name == 'ASC' then
        if #a == 0 then fault('ILLEGAL FUNCTION CALL') end
        return a:byte(1)
    end
    if name == 'VAL' then
        local word = a:match('^ *([+%-]?%d+)')
        return self:checked(word and tonumber(word) or 0)
    end
    if name == 'CHR$' then
        if a < 32 or a > 126 then fault('ILLEGAL FUNCTION CALL') end
        return string.char(a)
    end
    if name == 'STR$' then return tostring(a) end
    if name == 'LEFT$' or name == 'RIGHT$' then
        if b < 0 then fault('ILLEGAL FUNCTION CALL') end
        if name == 'LEFT$' then return a:sub(1, b) end
        if b == 0 then return '' end
        return a:sub(-math.min(b, #a))
    end
    if name == 'MID$' then
        if b < 1 or (c and c < 0) then fault('ILLEGAL FUNCTION CALL') end
        if c then return a:sub(b, b + c - 1) end
        return a:sub(b)
    end
    if name == 'INSTR' then
        if b == '' then return 1 end
        return a:find(b, 1, true) or 0
    end
    syntax()
end

function Machine:line(number)
    local entry = self.entries[number]
    if not entry then fault('UNDEFINED LINE NUMBER') end
    return entry
end

function Machine:push(frame)
    if #self.stack == 100 then fault('OUT OF MEMORY') end
    self.stack[#self.stack + 1] = frame
end

function Machine:search(kind, name)
    name = name or ''
    for i = #self.stack, 1, -1 do
        local frame = self.stack[i]
        if frame.kind == 'GOSUB' then break end
        if frame.kind == kind and (name == '' or name == frame.name) then
            return i
        end
    end
    return 0
end

function Machine:matching(s, opening, closing)
    local start
    for i, entry in ipairs(self.sequence) do
        if entry == s then start = i; break end
    end
    local depth = 0
    for i = start + 1, #self.sequence do
        local t = self.sequence[i]
        if t.kind == opening then
            depth = depth + 1
        elseif t.kind == closing then
            if depth == 0 then return t.next end
            depth = depth - 1
        end
    end
    fault(opening .. ' WITHOUT ' .. closing)
end

function Machine:subroutine(number, after)
    local target = self:line(number)
    self:push({kind = 'GOSUB', position = after})
    return target
end

function Machine:execute(s)
    local following = s.next
    if s.kind == 'assign' then
        local place = self:address(s.target)
        self:store(place, self:evaluate(s.expr))
    elseif s.kind == 'PRINT' then
        for _, item in ipairs(s.items) do
            if item.kind == ',' then
                self.buffer = self.buffer .. string.rep(' ', 10 - #self.buffer % 10)
            elseif item.kind ~= ';' then
                local value = self:evaluate(item.expr)
                if item.kind == 'value' then
                    self.buffer = self.buffer .. tostring(value)
                else
                    if value < 0 then fault('ILLEGAL FUNCTION CALL') end
                    local count = item.kind == 'SPC' and value or
                                  math.max(0, value - #self.buffer)
                    self.buffer = self.buffer .. string.rep(' ', count)
                end
            end
        end
        local last = s.items[#s.items]
        if not last or (last.kind ~= ';' and last.kind ~= ',') then
            self:end_line()
        end
    elseif s.kind == 'INPUT' or s.kind == 'READ' then
        for _, target in ipairs(s.targets) do
            local place = self:address(target)
            local value
            if s.kind == 'READ' then
                if self.data_position > #self.data then fault('OUT OF DATA') end
                value = self.data[self.data_position].value
                self.data_position = self.data_position + 1
                if value_type(value) ~= target.type then fault('TYPE MISMATCH') end
            else
                while true do
                    if self.input_position > #self.inputs then fault('INPUT PAST END') end
                    local text = self.inputs[self.input_position]
                    self.input_position = self.input_position + 1
                    if target.type == 'S' then
                        value = text
                        break
                    end
                    local n = tonumber(text)
                    if text:match('^%-?%d+$') and n and n >= -32768 and n <= 32767 then
                        value = n
                        break
                    end
                    self:message('?REDO FROM START')
                end
            end
            self:store(place, value)
        end
    elseif s.kind == 'RESTORE' then
        if #s.numbers == 0 then
            self.data_position = 1
        else
            self:line(s.numbers[1])
            self.data_position = #self.data + 1
            for i, item in ipairs(self.data) do
                if item.line >= s.numbers[1] then
                    self.data_position = i
                    break
                end
            end
        end
    elseif s.kind == 'IF' then
        local chosen = s.clauses[self:evaluate(s.expr) == 0 and 2 or 1]
        if chosen then
            if chosen.line then following = self:line(chosen.line)
            else following = chosen.body[1] end
        end
    elseif s.kind == 'GOTO' then
        following = self:line(s.numbers[1])
    elseif s.kind == 'GOSUB' then
        following = self:subroutine(s.numbers[1], following)
    elseif s.kind == 'ON' then
        local n = self:evaluate(s.expr)
        if n < 0 then fault('ILLEGAL FUNCTION CALL') end
        if n >= 1 and n <= #s.numbers then
            if s.mode == 'GOTO' then
                following = self:line(s.numbers[n])
            else
                following = self:subroutine(s.numbers[n], following)
            end
        end
    elseif s.kind == 'RETURN' then
        local index = 0
        for i = #self.stack, 1, -1 do
            if self.stack[i].kind == 'GOSUB' then index = i; break end
        end
        if index == 0 then fault('RETURN WITHOUT GOSUB') end
        following = self.stack[index].position
        for i = #self.stack, index, -1 do self.stack[i] = nil end
    elseif s.kind == 'FOR' then
        local start = self:evaluate(s.expressions[1])
        local final = self:evaluate(s.expressions[2])
        local step = self:evaluate(s.expressions[3])
        if step == 0 then fault('ILLEGAL FUNCTION CALL') end
        local index = self:search('FOR', s.name)
        if index > 0 then
            for i = #self.stack, index, -1 do self.stack[i] = nil end
        end
        self.variables[s.name] = start
        if (step > 0 and start > final) or (step < 0 and start < final) then
            following = self:matching(s, 'FOR', 'NEXT')
        else
            self:push({kind = 'FOR', position = following,
                       name = s.name, final = final, step = step})
        end
    elseif s.kind == 'NEXT' then
        local index = self:search('FOR', s.name)
        if index == 0 then fault('NEXT WITHOUT FOR') end
        for i = #self.stack, index + 1, -1 do self.stack[i] = nil end
        local frame = self.stack[index]
        local value = self:checked(self:get(frame.name) + frame.step)
        self.variables[frame.name] = value
        if (frame.step > 0 and value > frame.final) or
           (frame.step < 0 and value < frame.final) then
            self.stack[index] = nil
        else
            following = frame.position
        end
    elseif s.kind == 'WHILE' then
        if self:evaluate(s.expr) == 0 then
            following = self:matching(s, 'WHILE', 'WEND')
        else
            self:push({kind = 'WHILE', position = s})
        end
    elseif s.kind == 'WEND' then
        local index = self:search('WHILE')
        if index == 0 then fault('WEND WITHOUT WHILE') end
        following = self.stack[index].position
        for i = #self.stack, index, -1 do self.stack[i] = nil end
    elseif s.kind == 'DIM' then
        for _, target in ipairs(s.targets) do
            local name = target.value
            local bounds = {}
            for _, e in ipairs(target.args) do
                bounds[#bounds + 1] = self:evaluate(e)
            end
            if self.arrays[name] then fault('DUPLICATE DEFINITION') end
            local count = 1
            for _, bound in ipairs(bounds) do
                if bound < 0 then fault('ILLEGAL FUNCTION CALL') end
                count = count * (bound + 1)
            end
            if count > 10000 then fault('OUT OF MEMORY') end
            self:declare(name, bounds)
        end
    elseif s.kind == 'RANDOMIZE' then
        local value = self:evaluate(s.expr)
        if value < 1 then fault('ILLEGAL FUNCTION CALL') end
        self.random = value
    elseif s.kind == 'handler' then
        if s.numbers[1] ~= 0 then self:line(s.numbers[1]) end
        self.handler = s.numbers[1]
    elseif s.kind == 'RESUME' then
        if not self.handling then fault('RESUME WITHOUT ERROR') end
        if s.mode == 'line' then
            following = self:line(s.numbers[1])
        elseif s.mode == 'NEXT' then
            following = self.remembered.next
        else
            following = self.remembered
        end
        self.handling = false
    elseif s.kind == 'STOP' then
        self:message('BREAK IN LINE ' .. s.line)
        return nil
    elseif s.kind == 'END' then
        return nil
    end
    return following
end

function Machine:connect(body, after, number)
    local following = after
    for i = #body, 1, -1 do
        local s = body[i]
        s.line = number
        s.next = following
        for _, clause in ipairs(s.clauses) do
            self:connect(clause.body, following, number)
        end
        following = s
    end
end

function Machine:finish()
    if #self.buffer > 0 then self:end_line() end
    self.output[#self.output + 1] = 'READY'
    return self.output
end

function Machine:run(source)
    local parsed = {}
    local numbers = {}
    for number in pairs(source) do numbers[#numbers + 1] = number end
    table.sort(numbers)
    for _, number in ipairs(numbers) do
        local ok, result = pcall(function()
            return Parser.new(tokenize(source[number])):parse()
        end)
        if not ok then
            self:message('ERROR IN LINE ' .. number .. ': SYNTAX ERROR')
            return self:finish()
        end
        parsed[#parsed + 1] = {number = number, body = result}
    end
    local after = nil
    for i = #parsed, 1, -1 do
        local entry = parsed[i]
        self:connect(entry.body, after, entry.number)
        self.entries[entry.number] = entry.body[1]
        after = entry.body[1]
    end
    for _, entry in ipairs(parsed) do
        for _, s in ipairs(entry.body) do
            self.sequence[#self.sequence + 1] = s
            if s.kind == 'DATA' then
                for _, value in ipairs(s.values) do
                    self.data[#self.data + 1] = {line = s.line, value = value}
                end
            end
        end
    end
    local position = after
    while position do
        local stmt = position
        local ok, result = pcall(function() return self:execute(stmt) end)
        if ok then
            position = result
        else
            local failure = type(result) == 'table' and result.message or 'OVERFLOW'
            if self.handler ~= 0 and not self.handling then
                self.err = error_codes[failure] or 0
                self.erl = stmt.line
                self.remembered = stmt
                self.handling = true
                local found, target = pcall(function() return self:line(self.handler) end)
                if found then
                    position = target
                else
                    self:message('ERROR IN LINE ' .. stmt.line .. ': ' ..
                                 (type(target) == 'table' and target.message or failure))
                    position = nil
                end
            else
                self:message('ERROR IN LINE ' .. stmt.line .. ': ' .. failure)
                position = nil
            end
        end
    end
    return self:finish()
end

local lines = {}
for line in io.lines() do lines[#lines + 1] = line end
local programs = tonumber(lines[1])
local cursor = 2
local output = {}
for _ = 1, programs do
    local source = {}
    while lines[cursor] ~= 'RUN' do
        local number, content = lines[cursor]:match('^(%d+)%s*(.*)$')
        number = tonumber(number)
        if content == '' then source[number] = nil
        else source[number] = content end
        cursor = cursor + 1
    end
    cursor = cursor + 1
    local inputs = {}
    while lines[cursor] ~= 'END' do
        inputs[#inputs + 1] = lines[cursor]
        cursor = cursor + 1
    end
    cursor = cursor + 1
    local result = Machine.new(inputs):run(source)
    for _, text in ipairs(result) do output[#output + 1] = text end
end
io.write(table.concat(output, '\n'), '\n')
