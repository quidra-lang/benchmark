local T = require("terms")
local R = {}
R.__index = R
R.symbols, R.infix, R.prefix = {}, {}, { ["\\+"] = 900, ["-"] = 200 }
for character in ("+-*/\\^<>=~:.?@#&$"):gmatch(".") do R.symbols[character] = true end
for _, group in ipairs({
    { 1200, "xfx", ":-" }, { 1100, "xfy", ";" }, { 1050, "xfy", "->" }, { 1000, "xfy", "," },
    { 700, "xfx", "=", "\\=", "==", "\\==", "is", "=:=", "=\\=", "<", ">", "=<", ">=", "=.." },
    { 500, "yfx", "+", "-" }, { 400, "yfx", "*", "/", "//", "mod", "rem" }
}) do
    for i = 3, #group do
        local priority, kind = group[1], group[2]
        R.infix[group[i]] = { priority, kind == "yfx" and priority or priority - 1, kind == "xfy" and priority or priority - 1 }
    end
end
local function digit(c) return c >= "0" and c <= "9" and c ~= "" end
local function lower(c) return c >= "a" and c <= "z" and c ~= "" end
local function letter(c) return lower(c) or c >= "A" and c <= "Z" and c ~= "" end
local function alpha(c) return letter(c) or digit(c) or c == "_" end
function R.tokenize(text, column)
    local result, position, line, space = {}, 1, 1, true
    column = column or 1
    while position <= #text do
        local c = text:sub(position, position)
        if c == " " or c == "\n" then
            if c == "\n" then line, column = line + 1, 1 else column = column + 1 end
            position, space = position + 1, true
        elseif c == "%" then
            local finish = text:find("\n", position, true) or #text + 1
            column, position, space = column + finish - position, finish, true
        else
            local start, start_column, kind, value = position, column
            if digit(c) then
                position = position + 1
                while digit(text:sub(position, position)) do position = position + 1 end
                value, kind = 0, "integer"
                for i = start, position - 1 do
                    value = value * 10 + text:byte(i) - 48
                    if value > 2147483647 then kind, value = "invalid", "integer too large"; break end
                end
            elseif letter(c) or c == "_" then
                position = position + 1
                while alpha(text:sub(position, position)) do position = position + 1 end
                value, kind = text:sub(start, position - 1), lower(c) and "name" or "variable"
            elseif R.symbols[c] then
                position = position + 1
                while R.symbols[text:sub(position, position)] do position = position + 1 end
                value = text:sub(start, position - 1)
                local next_character = text:sub(position, position)
                kind = value == "." and (position > #text or next_character == " " or next_character == "\n" or next_character == "%") and "end" or "name"
            elseif c == "!" or c == ";" then kind, value, position = "name", c, position + 1
            elseif c ~= "" and (",|()[]"):find(c, 1, true) then kind, value, position = "punct", c, position + 1
            elseif c == "'" then
                position = position + 1
                local represented, incorrect = {}, false
                while true do
                    local current = text:sub(position, position)
                    if position > #text or current == "\n" then kind, value = "invalid", "unterminated quoted atom"; break
                    elseif current == "'" then
                        if text:sub(position + 1, position + 1) == "'" then represented[#represented + 1], position = "'", position + 2
                        else
                            position, kind = position + 1, incorrect and "invalid" or "quoted"
                            value = incorrect and "undefined escape sequence" or table.concat(represented)
                            break
                        end
                    elseif current == "\\" then
                        position = position + 1
                        current = text:sub(position, position)
                        if position <= #text and current ~= "\n" then
                            local escapes = { n = "\n", t = "\t", ["\\"] = "\\", ["'"] = "'" }
                            if not escapes[current] then incorrect = true end
                            represented[#represented + 1], position = escapes[current] or current, position + 1
                        end
                    else represented[#represented + 1], position = current, position + 1 end
                end
            else kind, value, position = "invalid", "illegal character '" .. c .. "'", position + 1 end
            result[#result + 1] = { kind = kind, value = value, spelling = text:sub(start, position - 1), line = line, column = start_column, space = space, index = #result + 1 }
            column, space = column + position - start, false
        end
    end
    result[#result + 1] = { kind = "eof", spelling = "", line = line, column = column, space = space, index = #result + 1 }
    return result
end
function R.fail(token, message)
    if not message then
        if token.kind == "invalid" then message = token.value
        elseif token.kind == "eof" then message = "unexpected end of file"
        elseif token.kind == "end" then message = "unexpected end of clause"
        elseif token.kind == "name" and R.infix[token.value] then message = "operator priority clash"
        else message = 'unexpected "' .. token.spelling .. '"' end
    end
    error({ category = "syntax", token = token, message = message }, 0)
end
function R.new(text, column) return setmetatable({ tokens = R.tokenize(text, column), position = 1, names = {}, counts = {}, order = {} }, R) end
function R:peek() return self.tokens[self.position] end
function R:take()
    local token = self:peek()
    if token.kind ~= "eof" then self.position = self.position + 1 end
    return token
end
function R:punctuation(value) local token = self:peek(); return token.kind == "punct" and token.value == value end
function R:expect(value) local token = self:take(); if token.kind ~= "punct" or token.value ~= value then R.fail(token) end end
function R:clause(query)
    self.names, self.counts, self.order = {}, {}, {}
    local term = self:term(1200)
    local token = self:take()
    if token.kind ~= "end" then R.fail(token) end
    if query and self:peek().kind ~= "eof" then R.fail(self:peek()) end
    return term
end
function R:term(limit)
    local term, priority = self:primary(limit)
    while true do
        local token = self:peek()
        local operator = (token.kind == "name" and R.infix[token.value]) or (token.kind == "punct" and token.value == "," and R.infix[","])
        if not operator or operator[1] > limit or priority > operator[2] then return term, priority end
        self:take()
        local argument = self:term(operator[3])
        term, priority = T.compound(token.value, term, argument), operator[1]
    end
end
function R:can_start()
    local token = self:peek()
    return token.kind == "integer" or token.kind == "variable" or token.kind == "quoted"
        or token.kind == "punct" and (token.value == "(" or token.value == "[")
        or token.kind == "name" and (not R.infix[token.value] or R.prefix[token.value] ~= nil)
end
function R:primary(limit)
    local token = self:take()
    if token.kind == "integer" then return token.value, 0 end
    if token.kind == "variable" then
        local name = token.value
        if not self.counts[name] then self.order[#self.order + 1] = name end
        self.counts[name] = (self.counts[name] or 0) + 1
        if name == "_" then return T.variable(), 0 end
        if not self.names[name] then self.names[name] = T.variable() end
        return self.names[name], 0
    end
    if token.kind == "punct" and token.value == "(" then local term = self:term(1200); self:expect(")"); return term, 0 end
    if token.kind == "punct" and token.value == "[" then
        if self:punctuation("]") then self:take(); return "[]", 0 end
        local elements = { (self:term(999)) }
        while self:punctuation(",") do self:take(); elements[#elements + 1] = self:term(999) end
        local tail = "[]"
        if self:punctuation("|") then self:take(); tail = self:term(999) end
        self:expect("]")
        return T.make_list(elements, tail), 0
    end
    if token.kind == "name" or token.kind == "quoted" then
        if self:punctuation("(") and not self:peek().space then
            self:take()
            local args = { (self:term(999)) }
            while self:punctuation(",") do self:take(); args[#args + 1] = self:term(999) end
            self:expect(")")
            return T.application(token.value, args), 0
        end
        if token.kind == "name" and token.value == "-" and self:peek().kind == "integer" and not self:peek().space then return -self:take().value, 0 end
        if token.kind == "name" and R.prefix[token.value] and self:can_start() then
            local priority = R.prefix[token.value]
            if priority > limit then R.fail(token, "operator priority clash") end
            return T.compound(token.value, (self:term(priority))), priority
        end
        return token.value, 0
    end
    R.fail(token)
end
return R
