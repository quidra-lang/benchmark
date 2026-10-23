local output = {}
local compile_only = {}
local interpret_only = {[":"]=true,[":NONAME"]=true,FORGET=true}
local both_modes = {['."']=true,["("]=true,["\\"]=true,TO=true,IS=true}
for name in ('IF ELSE THEN DO ?DO LOOP +LOOP LEAVE UNLOOP I J BEGIN UNTIL WHILE REPEAT AGAIN CASE OF ENDOF ENDCASE EXIT RECURSE DOES> ; >R R> R@ ABORT" [\'] {:'):gmatch("%S+") do compile_only[name] = true end
local builtin_names = "+ - * / MOD /MOD */ */MOD NEGATE ABS MIN MAX 1+ 1- 2* 2/ = <> < > 0= 0<> 0< 0> WITHIN TRUE FALSE AND OR XOR INVERT DUP ?DUP DROP SWAP OVER ROT -ROT NIP TUCK 2DUP 2DROP 2SWAP 2OVER DEPTH PICK ROLL . .R .S ? CR EMIT SPACE SPACES BL ! @ +! , ALLOT HERE CELLS CELL+ BASE HEX DECIMAL CREATE VARIABLE CONSTANT VALUE DEFER ' EXECUTE CATCH THROW ABORT WORDS"
local function problem(word, reason, code)
    error({forth=true, word=word, reason=reason, code=code}, 0)
end
local function syntax(word, reason) problem(word, reason) end
local function flag(value) return value and -1 or 0 end
local function copy(list) local result = {}; for i, value in ipairs(list) do result[i] = value end; return result end

local Machine = {}
Machine.__index = Machine
function Machine.new()
    local self = setmetatable({data={}, returns={}, memory={10}, dictionary={}, builtins={}, tokens={}, token_numbers={}, controls={}, depth=0, pending=""}, Machine)
    for name in builtin_names:gmatch("%S+") do self.builtins[name] = {name=name, kind="builtin"} end
    return self
end
function Machine:read()
    while self.position <= #self.line and self.line:sub(self.position, self.position) == " " do self.position = self.position + 1 end
    local start = self.position
    while self.position <= #self.line and self.line:sub(self.position, self.position) ~= " " do self.position = self.position + 1 end
    if start == self.position then return nil end
    return self.line:sub(start, self.position - 1)
end
function Machine:read_name(raw)
    local name = self:read()
    if not name then problem(raw, "missing name", -16) end
    return name
end
function Machine:lookup(name)
    name = name:upper()
    for i = #self.dictionary, 1, -1 do if self.dictionary[i].name == name then return self.dictionary[i] end end
    return self.builtins[name]
end
function Machine:numeric(raw, base)
    if #raw == 3 and raw:sub(1, 1) == "'" and raw:sub(3, 3) == "'" then return raw:byte(2) end
    local text, first = raw:upper(), raw:sub(1, 1)
    if first == "$" then base, text = 16, text:sub(2)
    elseif first == "#" then base, text = 10, text:sub(2)
    elseif first == "%" then base, text = 2, text:sub(2)
    elseif base < 2 or base > 36 then problem(raw, "invalid base", -40) end
    local negative = text:sub(1, 1) == "-"
    if negative then text = text:sub(2) end
    if text == "" then return nil end
    local digits = {}
    for i = 1, #text do
        local c, digit = text:byte(i), -1
        if c >= 48 and c <= 57 then digit = c - 48 elseif c >= 65 and c <= 90 then digit = c - 65 + 10 end
        if digit < 0 or digit >= base then return nil end
        digits[i] = digit
    end
    local value = 0
    for _, digit in ipairs(digits) do value = value * base + digit end
    return negative and -value or value
end
function Machine:check_name(raw)
    local name = raw:upper()
    if compile_only[name] or interpret_only[name] or both_modes[name] or self:numeric(raw, 10) ~= nil then problem(raw, "invalid name", -19) end
end
function Machine:take(count, raw)
    if #self.data < count then problem(raw, "stack underflow", -4) end
    local result, start = {}, #self.data - count
    for i = 1, count do result[i] = self.data[start + i] end
    for i = #self.data, start + 1, -1 do self.data[i] = nil end
    return result
end
function Machine:push(value, raw)
    self.data[#self.data + 1] = value
    if #self.data > 1000 then problem(raw, "stack overflow", -3) end
end
function Machine:return_need(count, raw) if #self.returns < count then problem(raw, "return stack underflow", -6) end end
function Machine:return_push(value, raw)
    self.returns[#self.returns + 1] = value
    if #self.returns > 1000 then problem(raw, "return stack overflow", -5) end
end
function Machine:address(value, raw)
    if value < 0 or value % 8 ~= 0 or value >= #self.memory * 8 then problem(raw, "invalid address", -9) end
    return value // 8 + 1
end
function Machine:format(value, raw)
    local base = self.memory[1]
    if base < 2 or base > 36 then problem(raw, "invalid base", -40) end
    local negative, digits = value < 0, "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    if negative then value = -value end
    local result = ""
    repeat
        local digit = value % base
        result = digits:sub(digit + 1, digit + 1) .. result
        value = value // base
    until value == 0
    return (negative and "-" or "") .. result
end
function Machine:write(text) self.pending = self.pending .. text end
function Machine:flush() output[#output + 1] = self.pending:gsub(" +$", ""); self.pending = "" end
function Machine:execution_token(word)
    if not self.token_numbers[word] then self.tokens[#self.tokens + 1] = word; self.token_numbers[word] = #self.tokens end
    return self.token_numbers[word]
end
function Machine:valid_token(value, raw)
    if value < 1 or value > #self.tokens then problem(raw, "invalid argument", -24) end
    return self.tokens[value]
end
function Machine:execute_token(value, raw)
    local word = self:valid_token(value, raw)
    self:execute(word, word.name)
end
function Machine:add_action(action) self.compiling.actions[#self.compiling.actions + 1] = action; return #self.compiling.actions end
function Machine:top_control(raw, ...)
    local top = self.controls[#self.controls]
    for _, kind in ipairs({...}) do if top and top.kind == kind then return top end end
    syntax(raw, "control structure mismatch")
end
function Machine:compile_control(raw, name)
    if name == "IF" then self.controls[#self.controls + 1] = {kind="IF", index=self:add_action({kind="zero", raw=raw})}
    elseif name == "ELSE" then
        local top = self:top_control(raw, "IF")
        local index = self:add_action({kind="jump", raw=raw})
        self.compiling.actions[top.index].target = #self.compiling.actions + 1
        top.kind, top.index = "ELSE", index
    elseif name == "THEN" then
        local top = self:top_control(raw, "IF", "ELSE")
        self.compiling.actions[top.index].target = #self.compiling.actions + 1
        table.remove(self.controls)
    elseif name == "BEGIN" then self.controls[#self.controls + 1] = {kind="BEGIN", start=#self.compiling.actions + 1}
    elseif name == "UNTIL" or name == "AGAIN" then
        local top = self:top_control(raw, "BEGIN")
        self:add_action({kind=name == "UNTIL" and "zero" or "jump", raw=raw, target=top.start})
        table.remove(self.controls)
    elseif name == "WHILE" then
        local top = self:top_control(raw, "BEGIN")
        top.kind, top.index = "WHILE", self:add_action({kind="zero", raw=raw})
    elseif name == "REPEAT" then
        local top = self:top_control(raw, "WHILE")
        self:add_action({kind="jump", raw=raw, target=top.start})
        self.compiling.actions[top.index].target = #self.compiling.actions + 1
        table.remove(self.controls)
    elseif name == "DO" or name == "?DO" then
        local index = self:add_action({kind=name, raw=raw})
        self.controls[#self.controls + 1] = {kind=name, index=index, start=index + 1, leaves={}}
    elseif name == "LOOP" or name == "+LOOP" then
        local top = self:top_control(raw, "DO", "?DO")
        self:add_action({kind=name, raw=raw, target=top.start})
        local finish = #self.compiling.actions + 1
        self.compiling.actions[top.index].target = finish
        for _, index in ipairs(top.leaves) do self.compiling.actions[index].target = finish end
        table.remove(self.controls)
    elseif name == "LEAVE" then
        local top
        for i = #self.controls, 1, -1 do if self.controls[i].kind == "DO" or self.controls[i].kind == "?DO" then top = self.controls[i]; break end end
        if not top then syntax(raw, "control structure mismatch") end
        top.leaves[#top.leaves + 1] = self:add_action({kind="LEAVE", raw=raw})
    elseif name == "CASE" then self.controls[#self.controls + 1] = {kind="CASE", ends={}}
    elseif name == "OF" then
        self:top_control(raw, "CASE")
        self.controls[#self.controls + 1] = {kind="OF", index=self:add_action({kind="OF", raw=raw})}
    elseif name == "ENDOF" then
        local top = self:top_control(raw, "OF")
        local index = self:add_action({kind="jump", raw=raw})
        self.compiling.actions[top.index].target = #self.compiling.actions + 1
        table.remove(self.controls)
        local parent = self:top_control(raw, "CASE")
        parent.ends[#parent.ends + 1] = index
    elseif name == "ENDCASE" then
        local top = self:top_control(raw, "CASE")
        self:add_action({kind="ENDCASE", raw=raw})
        for _, index in ipairs(top.ends) do self.compiling.actions[index].target = #self.compiling.actions + 1 end
        table.remove(self.controls)
    else return false end
    return true
end
function Machine:read_string(raw)
    if self.position > #self.line then syntax(raw, "unterminated string") end
    local start = self.position + 1
    local closing = self.line:find('"', start, true)
    if not closing then syntax(raw, "unterminated string") end
    self.position = closing + 1
    return self.line:sub(start, closing - 1)
end
function Machine:locals(raw)
    local names, ignored, closed = {}, false, false
    while true do
        local name = self:read()
        if not name then break end
        if name:upper() == ":}" then closed = true; break end
        if name == "--" then ignored = true end
        if not ignored then names[#names + 1] = name end
    end
    if not closed then syntax(raw, "unterminated locals") end
    local slots = {}
    for _, name in ipairs(names) do
        self:check_name(name)
        self.compiling.local_count = self.compiling.local_count + 1
        local slot = self.compiling.local_count
        self.compiling.local_names[name:upper()] = slot
        slots[#slots + 1] = slot
    end
    self:add_action({kind="locals", raw=raw, slots=slots})
end
function Machine:assign(raw, name)
    local target_name = self:read_name(raw)
    if name == "TO" and self.compiling then
        local slot = self.compiling.local_names[target_name:upper()]
        if slot then self:add_action({kind="localSet", raw=raw, target=slot}); return end
    end
    local target = self:lookup(target_name)
    if not target then problem(target_name, "undefined word", -13) end
    local required, reason = name == "TO" and "value" or "defer", name == "TO" and "not a value" or "not deferred"
    if target.kind ~= required then syntax(target_name, reason) end
    local action = {kind=name, raw=raw, word=target}
    if self.compiling then self:add_action(action) else self:runtime_action(action, {}) end
end
function Machine:process(raw)
    local name = raw:upper()
    if name == "\\" then self.position = #self.line + 1; return end
    if name == "(" then
        local closing = self.line:find(")", self.position, true)
        if not closing then syntax(raw, "unterminated comment") end
        self.position = closing + 1
        return
    end
    if not self.compiling and compile_only[name] then syntax(raw, "compile only") end
    if self.compiling and interpret_only[name] then syntax(raw, "interpret only") end
    if name == '."' or name == 'ABORT"' then
        local text = self:read_string(raw)
        if self.compiling then self:add_action({kind=name, raw=raw, text=text}) else self:write(text) end
        return
    end
    if name == "TO" or name == "IS" then self:assign(raw, name); return end
    if name == ":" or name == ":NONAME" then
        local raw_name = raw
        if name == ":" then raw_name = self:read_name(raw); self:check_name(raw_name) end
        self.compiling = {name=name == ":NONAME" and ":NONAME" or raw_name:upper(), raw_name=raw_name, kind="colon", here=#self.memory * 8, actions={}, local_names={}, local_count=0}
        self.controls = {}
        return
    end
    if name == "FORGET" then
        local target_name, index = self:read_name(raw), nil
        for i = #self.dictionary, 1, -1 do if self.dictionary[i].name == target_name:upper() then index = i; break end end
        if not index then problem(target_name, "undefined word", -13) end
        for i = #self.memory, self.dictionary[index].here // 8 + 1, -1 do self.memory[i] = nil end
        for i = #self.dictionary, index, -1 do self.dictionary[i] = nil end
        return
    end
    if self.compiling then
        if self:compile_control(raw, name) then return end
        if name == ";" then
            if #self.controls > 0 then
                local kind = self.controls[#self.controls].kind
                if kind == "ELSE" then kind = "IF" elseif kind == "WHILE" then kind = "BEGIN" end
                syntax(raw, "unclosed " .. kind)
            end
            local finished = self.compiling
            self.compiling = nil
            if finished.name == ":NONAME" then self:push(self:execution_token(finished), raw) else self.dictionary[#self.dictionary + 1] = finished end
            return
        elseif name == "DOES>" then
            if #self.controls > 0 then syntax(raw, "control structure mismatch") end
            self:add_action({kind="DOES>", raw=raw, word=self.compiling}); return
        elseif name == "EXIT" then self:add_action({kind="EXIT", raw=raw}); return
        elseif name == "RECURSE" then self:add_action({kind="call", raw=raw, word=self.compiling}); return
        elseif name == "[']" then
            local target_name = self:read_name(raw)
            local target = self:lookup(target_name)
            if not target then problem(target_name, "undefined word", -13) end
            self:add_action({kind="push", raw=raw, value=self:execution_token(target)}); return
        elseif name == "{:" then self:locals(raw); return end
        if name == ">R" or name == "R>" or name == "R@" or name == "I" or name == "J" or name == "UNLOOP" then self:add_action({kind=name, raw=raw}); return end
        local slot = self.compiling.local_names[name]
        if slot then self:add_action({kind="localGet", raw=raw, target=slot}); return end
        local target = self:lookup(raw)
        if target then self:add_action({kind="call", raw=raw, word=target}); return end
        local value = self:numeric(raw, self.memory[1])
        if value ~= nil then self:add_action({kind="push", raw=raw, value=value}); return end
        problem(raw, "undefined word", -13)
    end
    local target = self:lookup(raw)
    if target then self:execute(target, raw); return end
    local value = self:numeric(raw, self.memory[1])
    if value ~= nil then self:push(value, raw); return end
    problem(raw, "undefined word", -13)
end
function Machine:runtime_action(action, locals)
    local kind, raw = action.kind, action.raw
    if kind == "push" then self:push(action.value, raw)
    elseif kind == "call" then self:execute(action.word, raw)
    elseif kind == '."' then self:write(action.text)
    elseif kind == 'ABORT"' then if self:take(1, raw)[1] ~= 0 then problem(raw, action.text, -2) end
    elseif kind == "localGet" then self:push(locals[action.target], raw)
    elseif kind == "localSet" then locals[action.target] = self:take(1, raw)[1]
    elseif kind == "locals" then local values = self:take(#action.slots, raw); for i, slot in ipairs(action.slots) do locals[slot] = values[i] end
    elseif kind == "TO" then self.memory[action.word.address // 8 + 1] = self:take(1, raw)[1]
    elseif kind == "IS" then local value = self:take(1, raw)[1]; self:valid_token(value, raw); action.word.token = value
    elseif kind == ">R" then self:return_push(self:take(1, raw)[1], raw)
    elseif kind == "R>" then self:return_need(1, raw); self:push(table.remove(self.returns), raw)
    elseif kind == "R@" or kind == "I" or kind == "J" then local count = kind == "J" and 3 or 1; self:return_need(count, raw); self:push(self.returns[#self.returns - count + 1], raw)
    elseif kind == "UNLOOP" then self:return_need(2, raw); table.remove(self.returns); table.remove(self.returns) end
end
function Machine:definition(word, start, raw)
    if self.depth == 100 then problem(raw, "nesting too deep", -7) end
    self.depth = self.depth + 1
    local saved, locals, pc = #self.returns, {}, start
    for i = 1, word.local_count do locals[i] = 0 end
    while pc <= #word.actions do
        local action = word.actions[pc]
        pc = pc + 1
        local kind = action.kind
        if kind == "EXIT" then break
        elseif kind == "DOES>" then
            local newest = self.dictionary[#self.dictionary]
            if not newest or newest.kind ~= "create" then problem(action.raw, "no CREATE word", -31) end
            newest.does, newest.does_start = action.word, pc
            break
        elseif kind == "jump" then pc = action.target
        elseif kind == "zero" then if self:take(1, action.raw)[1] == 0 then pc = action.target end
        elseif kind == "DO" or kind == "?DO" then
            local values = self:take(2, action.raw)
            if kind == "?DO" and values[1] == values[2] then pc = action.target else self:return_push(values[1], action.raw); self:return_push(values[2], action.raw) end
        elseif kind == "LOOP" or kind == "+LOOP" then
            local step = kind == "+LOOP" and self:take(1, action.raw)[1] or 1
            self:return_need(2, action.raw)
            local index, limit = self.returns[#self.returns], self.returns[#self.returns - 1]
            local next_index = index + step
            if (index - limit < 0) ~= (next_index - limit < 0) then table.remove(self.returns); table.remove(self.returns)
            else self.returns[#self.returns] = next_index; pc = action.target end
        elseif kind == "LEAVE" then self:return_need(2, action.raw); table.remove(self.returns); table.remove(self.returns); pc = action.target
        elseif kind == "OF" then local values = self:take(2, action.raw); if values[1] ~= values[2] then self:push(values[1], action.raw); pc = action.target end
        elseif kind == "ENDCASE" then self:take(1, action.raw)
        else self:runtime_action(action, locals) end
    end
    for i = #self.returns, saved + 1, -1 do self.returns[i] = nil end
    self.depth = self.depth - 1
end
function Machine:execute(word, raw)
    while word.kind == "defer" do
        if not word.token then problem(raw, "deferred word not set", -21) end
        word = self:valid_token(word.token, raw)
        raw = word.name
    end
    if word.kind == "colon" then self:definition(word, 1, raw)
    elseif word.kind == "create" then self:push(word.address, raw); if word.does then self:definition(word.does, word.does_start, raw) end
    elseif word.kind == "variable" then self:push(word.address, raw)
    elseif word.kind == "constant" then self:push(word.value, raw)
    elseif word.kind == "value" then self:push(self.memory[word.address // 8 + 1], raw)
    else self:builtin(word.name, raw) end
end
local effects = {}
for _, entry in ipairs({{2,"+ - * / MOD /MOD MIN MAX = <> < > AND OR XOR SWAP OVER NIP TUCK 2DUP 2DROP .R ! +!"}, {3,"*/ */MOD WITHIN ROT -ROT"}, {4,"2SWAP 2OVER"}}) do for name in entry[2]:gmatch("%S+") do effects[name] = entry[1] end end
function Machine:builtin(name, raw)
    if name == "CREATE" or name == "VARIABLE" or name == "CONSTANT" or name == "VALUE" or name == "DEFER" then
        local raw_name = self:read_name(raw)
        self:check_name(raw_name)
        local value = 0
        if name == "CONSTANT" or name == "VALUE" then value = self:take(1, raw)[1] end
        self.dictionary[#self.dictionary + 1] = {name=raw_name:upper(), raw_name=raw_name, kind=name:lower(), here=#self.memory * 8, address=#self.memory * 8, value=value}
        if name == "VARIABLE" or name == "VALUE" then self.memory[#self.memory + 1] = value end
        return
    elseif name == "'" then
        local target_name = self:read_name(raw)
        local target = self:lookup(target_name)
        if not target then problem(target_name, "undefined word", -13) end
        self:push(self:execution_token(target), raw); return
    elseif name == "EXECUTE" then self:execute_token(self:take(1, raw)[1], raw); return
    elseif name == "CATCH" then
        local token = self:take(1, raw)[1]
        local target = self:valid_token(token, raw)
        local saved, return_size, depth = copy(self.data), #self.returns, self.depth
        local ok, caught = pcall(function() self:execute(target, target.name) end)
        local code = 0
        if not ok then
            if type(caught) ~= "table" or not caught.forth or caught.code == nil then error(caught, 0) end
            self.data = saved
            for i = #self.returns, return_size + 1, -1 do self.returns[i] = nil end
            self.depth, code = depth, caught.code
        end
        self:push(code, raw); return
    elseif name == "THROW" then local code = self:take(1, raw)[1]; if code ~= 0 then problem(raw, "exception " .. code, code) end; return
    elseif name == "ABORT" then problem(raw, "aborted", -1)
    elseif name == "WORDS" then for i = #self.dictionary, 1, -1 do self:write(self.dictionary[i].name .. " ") end; return
    elseif name == "CR" then self:flush(); return
    elseif name == "SPACE" then self:write(" "); return
    elseif name == ".S" then
        local count, values = self:format(#self.data, raw), {}
        for i, value in ipairs(self.data) do values[i] = self:format(value, raw) end
        self:write("<" .. count .. "> ")
        for _, value in ipairs(values) do self:write(value .. " ") end
        return
    elseif name == "TRUE" then self:push(-1, raw); return
    elseif name == "FALSE" then self:push(0, raw); return
    elseif name == "BL" then self:push(32, raw); return
    elseif name == "BASE" then self:push(0, raw); return
    elseif name == "HERE" then self:push(#self.memory * 8, raw); return
    elseif name == "DEPTH" then self:push(#self.data, raw); return
    elseif name == "HEX" then self.memory[1] = 16; return
    elseif name == "DECIMAL" then self.memory[1] = 10; return end
    local values = self:take(effects[name] or 1, raw)
    local a, b = values[1], values[2]
    local function push(...) for _, value in ipairs({...}) do self:push(value, raw) end end
    if name == "+" then push(a + b) elseif name == "-" then push(a - b) elseif name == "*" then push(a * b)
    elseif name == "/" or name == "MOD" or name == "/MOD" or name == "*/" or name == "*/MOD" then
        local dividend, divisor = a, b
        if #values == 3 then dividend, divisor = a * b, values[3] end
        if divisor == 0 then problem(raw, "division by zero", -10) end
        local q = dividend // divisor
        local r = dividend - divisor * q
        if name == "MOD" then push(r) elseif name == "/MOD" or name == "*/MOD" then push(r, q) else push(q) end
    elseif name == "NEGATE" then push(-a) elseif name == "ABS" then push(math.abs(a))
    elseif name == "MIN" then push(math.min(a, b)) elseif name == "MAX" then push(math.max(a, b))
    elseif name == "1+" then push(a + 1) elseif name == "1-" then push(a - 1) elseif name == "2*" then push(2 * a) elseif name == "2/" then push(a // 2)
    elseif name == "=" then push(flag(a == b)) elseif name == "<>" then push(flag(a ~= b)) elseif name == "<" then push(flag(a < b)) elseif name == ">" then push(flag(a > b))
    elseif name == "0=" then push(flag(a == 0)) elseif name == "0<>" then push(flag(a ~= 0)) elseif name == "0<" then push(flag(a < 0)) elseif name == "0>" then push(flag(a > 0))
    elseif name == "WITHIN" then push(flag(b <= a and a < values[3]))
    elseif name == "AND" then push(a & b) elseif name == "OR" then push(a | b) elseif name == "XOR" then push(a ~ b) elseif name == "INVERT" then push(~a)
    elseif name == "DUP" then push(a, a) elseif name == "?DUP" then push(a); if a ~= 0 then push(a) end
    elseif name == "DROP" or name == "2DROP" then
    elseif name == "SWAP" then push(b, a) elseif name == "OVER" then push(a, b, a)
    elseif name == "ROT" then push(b, values[3], a) elseif name == "-ROT" then push(values[3], a, b)
    elseif name == "NIP" then push(b) elseif name == "TUCK" then push(b, a, b) elseif name == "2DUP" then push(a, b, a, b)
    elseif name == "2SWAP" then push(values[3], values[4], a, b) elseif name == "2OVER" then push(a, b, values[3], values[4], a, b)
    elseif name == "PICK" or name == "ROLL" then
        if a < 0 then problem(raw, "invalid argument", -24) end
        if a >= #self.data then problem(raw, "stack underflow", -4) end
        local index = #self.data - a
        local value = self.data[index]
        if name == "ROLL" then table.remove(self.data, index) end
        push(value)
    elseif name == "." then self:write(self:format(a, raw) .. " ")
    elseif name == ".R" then local text = self:format(a, raw); self:write(string.rep(" ", math.max(0, b - #text)) .. text)
    elseif name == "?" then local address = self:address(a, raw); self:write(self:format(self.memory[address], raw) .. " ")
    elseif name == "EMIT" then if a < 32 or a > 126 then problem(raw, "invalid argument", -24) end; self:write(string.char(a))
    elseif name == "SPACES" then if a > 0 then self:write(string.rep(" ", a)) end
    elseif name == "!" then self.memory[self:address(b, raw)] = a
    elseif name == "@" then push(self.memory[self:address(a, raw)])
    elseif name == "+!" then local address = self:address(b, raw); self.memory[address] = self.memory[address] + a
    elseif name == "," then self.memory[#self.memory + 1] = a
    elseif name == "ALLOT" then if a < 0 or a % 8 ~= 0 then problem(raw, "invalid argument", -24) end; for _ = 1, a // 8 do self.memory[#self.memory + 1] = 0 end
    elseif name == "CELLS" then push(8 * a) elseif name == "CELL+" then push(a + 8) end
end
function Machine:process_line(line)
    self.line, self.position = line, 1
    local ok, caught = pcall(function()
        while true do local raw = self:read(); if not raw then break end; self:process(raw) end
    end)
    if not ok then
        if type(caught) ~= "table" or not caught.forth then error(caught, 0) end
        if #self.pending > 0 then self:flush() end
        output[#output + 1] = "ERROR " .. caught.word .. ": " .. caught.reason
        self.data, self.returns, self.compiling, self.controls, self.depth = {}, {}, nil, {}, 0
    elseif #self.pending > 0 then self:flush() end
end

local machine = Machine.new()
for line in io.lines() do
    if line == "BYE" then
        if machine.compiling then output[#output + 1] = "ERROR " .. machine.compiling.raw_name .. ": unterminated definition" end
        break
    end
    machine:process_line(line)
end
if #output > 0 then io.write(table.concat(output, "\n"), "\n") end
