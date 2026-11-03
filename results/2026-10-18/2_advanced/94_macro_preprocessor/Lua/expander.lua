local L = require("lexer")
local D = require("definitions")
local X = {}
X.__index = X
local function union(a, b)
    local result = {}
    for name in pairs(a) do result[name] = true end
    for name in pairs(b) do result[name] = true end
    return result
end
local function intersection(a, b)
    local result = {}
    for name in pairs(a) do if b[name] then result[name] = true end end
    return result
end
function X.new(macros, diagnostic)
    return setmetatable({ macros = macros, diagnostic = diagnostic, counter = 0,
        builtin_counts = { __COUNTER__ = 0, __FILE__ = 0, __LINE__ = 0 } }, X)
end
function X:error(context, token, message) self.diagnostic(context:position(token.line), "error", message) end
function X:builtin(token, context)
    self.builtin_counts[token.spelling] = self.builtin_counts[token.spelling] + 1
    local kind, spelling = "number"
    if token.spelling == "__FILE__" then kind, spelling = "string", '"' .. context.display_file .. '"'
    elseif token.spelling == "__LINE__" then spelling = tostring(context:position(token.line)[2])
    else spelling, self.counter = tostring(self.counter), self.counter + 1 end
    return L.token(kind, spelling, token.line, token.space)
end
function X:collect(pending, head, tail, macro, token, context)
    local arguments, separators, nesting, closing, consumed = { {} }, {}, 0, false, false
    for i = head + 1, tail do
        local current = pending[i]
        if current.spelling == ")" and nesting == 0 then closing, consumed = current, i - head + 1; break end
        if current.spelling == "," and nesting == 0 then
            separators[#separators + 1], arguments[#arguments + 1] = current, {}
        else
            if current.spelling == "(" then nesting = nesting + 1 elseif current.spelling == ")" then nesting = nesting - 1 end
            local argument = arguments[#arguments]
            argument[#argument + 1] = current
        end
    end
    if not closing then self:error(context, token, 'unterminated argument list invoking macro "' .. macro.name .. '"'); return false end
    local count, fixed, err = #arguments, #macro.parameters - (macro.variadic and 1 or 0)
    if not macro.variadic and fixed == 0 and (count ~= 1 or #arguments[1] > 0) then
        err = string.format('macro "%s" passed %d arguments, but takes just 0', macro.name, count)
    elseif count < fixed then err = string.format('macro "%s" requires %d arguments, but only %d given', macro.name, fixed, count)
    elseif count > fixed and not macro.variadic then err = string.format('macro "%s" passed %d arguments, but takes just %d', macro.name, count, fixed) end
    if err then self:error(context, token, err); return false end
    local raw = {}
    for i = 1, fixed do raw[macro.parameters[i]] = arguments[i] end
    if macro.variadic then
        local variable = {}
        for i = fixed + 1, count do
            if i > fixed + 1 then variable[#variable + 1] = separators[i - 1] end
            for _, current in ipairs(arguments[i]) do variable[#variable + 1] = current end
        end
        raw.__VA_ARGS__ = variable
    end
    return raw, consumed, closing
end
function X:stringize(tokens, sharp)
    local pieces = {}
    for i, token in ipairs(tokens) do
        if i > 1 and token.space then pieces[#pieces + 1] = " " end
        local spelling = token.spelling
        if token.kind == "string" or token.kind == "character" then spelling = spelling:gsub("\\", "\\\\"):gsub('"', '\\"') end
        pieces[#pieces + 1] = spelling
    end
    return L.token("string", '"' .. table.concat(pieces) .. '"', sharp.line, sharp.space)
end
function X:paste(left, right, token, context)
    if left.kind == "placemarker" then return { L.clone(right, { space = left.space }) }
    elseif right.kind == "placemarker" then return { L.clone(left) } end
    local spelling = left.spelling .. right.spelling
    local kind = L.single_token(spelling)
    if kind then return { L.token(kind, spelling, left.line, left.space, intersection(left.hide, right.hide)) } end
    self:error(context, token, 'pasting "' .. left.spelling .. '" and "' .. right.spelling .. '" does not give a valid preprocessing token')
    return { L.clone(left), L.clone(right, { space = false }) }
end
function X:substitute(macro, raw, token, hide, context)
    local replacement, items, expanded, index = macro.replacement, {}, {}, 1
    while index <= #replacement do
        local current = replacement[index]
        if current.spelling == "#" and macro.parameters then
            items[#items + 1] = { self:stringize(raw[replacement[index + 1].spelling], current) }
            index = index + 2
        else
            if current.spelling == "##" then items[#items + 1] = { paste = true, token = current }
            elseif current.kind == "identifier" and raw[current.spelling] then
                local before, after = replacement[index - 1], replacement[index + 1]
                local adjacent = (before and before.spelling == "##") or (after and after.spelling == "##")
                local sequence
                if adjacent then sequence = raw[current.spelling]
                else
                    if not expanded[current.spelling] then expanded[current.spelling] = self:expand(raw[current.spelling], context) end
                    sequence = expanded[current.spelling]
                end
                local item = {}
                if #sequence > 0 then
                    for i, entry in ipairs(sequence) do item[i] = L.clone(entry) end
                    item[1].space = current.space
                else item[1] = L.token("placemarker", "", current.line, current.space) end
                items[#items + 1] = item
            else items[#items + 1] = { L.clone(current) } end
            index = index + 1
        end
    end
    local pasted = {}
    index = 1
    while index <= #items do
        local item = items[index]
        if item.paste then
            local left, right = table.remove(pasted), items[index + 1]
            if right.paste then right = { right.token } end
            for _, entry in ipairs(self:paste(left, right[1], token, context)) do pasted[#pasted + 1] = entry end
            for i = 2, #right do pasted[#pasted + 1] = L.clone(right[i]) end
            index = index + 2
        else
            for _, entry in ipairs(item) do pasted[#pasted + 1] = entry end
            index = index + 1
        end
    end
    local result, carry = {}, false
    for _, current in ipairs(pasted) do
        if current.kind == "placemarker" then carry = carry or current.space
        else
            result[#result + 1] = L.clone(current, { line = token.line, space = current.space or carry, hide = union(current.hide, hide) })
            carry = false
        end
    end
    if #result > 0 then result[1].space = token.space end
    return result
end
function X:expand(sequence, context)
    local pending, head, tail, result = {}, 1, #sequence, {}
    for i, token in ipairs(sequence) do pending[i] = L.clone(token) end
    while head <= tail do
        local token = pending[head]
        pending[head], head = nil, head + 1
        local macro = self.macros[token.spelling]
        if token.kind ~= "identifier" or token.hide[token.spelling] then result[#result + 1] = token
        elseif D.builtins[token.spelling] then result[#result + 1] = self:builtin(token, context)
        elseif not macro or (macro.parameters and (head > tail or pending[head].spelling ~= "(")) then result[#result + 1] = token
        else
            local raw, hide = {}, union(token.hide, { [macro.name] = true })
            if macro.parameters then
                local consumed, closing
                raw, consumed, closing = self:collect(pending, head, tail, macro, token, context)
                if raw then
                    for _ = 1, consumed do pending[head], head = nil, head + 1 end
                    hide = union(intersection(token.hide, closing.hide), { [macro.name] = true })
                end
            end
            if not raw then result[#result + 1] = token
            else
                local produced = self:substitute(macro, raw, token, hide, context)
                macro.expanded = macro.expanded + 1
                if #produced == 0 and token.space and head <= tail then pending[head] = L.clone(pending[head], { space = true }) end
                for i = #produced, 1, -1 do head = head - 1; pending[head] = produced[i] end
            end
        end
    end
    return result
end
return X
