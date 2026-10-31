local M = {}
function M.is_nonterminal(symbol)
    return symbol:sub(1, 1) == "<" and symbol:sub(-1) == ">"
end
function M.alternative(symbols)
    return #symbols == 0 and "%empty" or table.concat(symbols, " ")
end
function M.production(lhs, rhs)
    return lhs .. " -> " .. M.alternative(rhs)
end
function M.copy(grammar)
    local result = {order = {table.unpack(grammar.order)}, rules = {}, start = grammar.start}
    for _, lhs in ipairs(grammar.order) do
        result.rules[lhs] = {}
        for _, rhs in ipairs(grammar.rules[lhs]) do
            result.rules[lhs][#result.rules[lhs] + 1] = {table.unpack(rhs)}
        end
    end
    return result
end
function M.same(first, second)
    if #first ~= #second then
        return false
    end
    for i, value in ipairs(first) do
        if value ~= second[i] then
            return false
        end
    end
    return true
end
function M.lex(line)
    local tokens, cursor = {}, 1
    while cursor <= #line do
        local character = line:sub(cursor, cursor)
        if character == " " then
            cursor = cursor + 1
        elseif character == "#" then
            break
        else
            local start, kind, value = cursor, "invalid", character
            if character == "<" then
                value = line:sub(cursor):match("^<[A-Za-z][A-Za-z0-9_]*>")
                if value then
                    kind, cursor = "nonterminal", cursor + #value
                end
            elseif character == '"' then
                value = line:sub(cursor):match('^"([^ "]+)"')
                if value then
                    kind, cursor = "terminal", cursor + #value + 2
                end
            elseif character:match("[A-Za-z]") then
                value = line:sub(cursor):match("^[A-Za-z][A-Za-z0-9_]*")
                kind, cursor = "word", cursor + #value
            elseif line:sub(cursor, cursor + 2) == "::=" then
                kind, value, cursor = "definition", "::=", cursor + 3
            elseif character == "|" then
                kind, cursor = "separator", cursor + 1
            elseif character == "%" then
                local name = line:sub(cursor + 1):match("^[A-Za-z]*")
                if name == "empty" or name == "start" or name == "token" then
                    kind, value, cursor = "directive", "%" .. name, cursor + #name + 1
                end
            end
            if kind == "invalid" then
                value, cursor = character, start + 1
            end
            tokens[#tokens + 1] = {kind = kind, value = value, start = start, finish = cursor - 1}
            if kind == "invalid" then
                break
            end
        end
    end
    return tokens
end
local function error_column(tokens, cursor)
    return tokens[cursor] and tokens[cursor].start or tokens[#tokens].finish + 1
end
local function alternatives(tokens, cursor)
    local result = {}
    while true do
        local rhs = {}
        if not tokens[cursor] then
            return nil, error_column(tokens, cursor)
        end
        if tokens[cursor].kind == "directive" and tokens[cursor].value == "%empty" then
            cursor = cursor + 1
        elseif tokens[cursor].kind == "nonterminal" or tokens[cursor].kind == "terminal" or tokens[cursor].kind == "word" then
            while tokens[cursor] and (tokens[cursor].kind == "nonterminal" or tokens[cursor].kind == "terminal" or tokens[cursor].kind == "word") do
                rhs[#rhs + 1] = tokens[cursor].value
                cursor = cursor + 1
            end
        else
            return nil, error_column(tokens, cursor)
        end
        result[#result + 1] = rhs
        if not tokens[cursor] then
            return result
        end
        if tokens[cursor].kind ~= "separator" then
            return nil, error_column(tokens, cursor)
        end
        cursor = cursor + 1
    end
end
local function line_form(tokens)
    if #tokens == 0 then
        return "blank"
    end
    local first = tokens[1]
    if first.kind == "nonterminal" then
        if not tokens[2] or tokens[2].kind ~= "definition" then
            return nil, nil, nil, error_column(tokens, 2)
        end
        local rhs, column = alternatives(tokens, 3)
        return rhs and "rule" or nil, first.value, rhs, column
    elseif first.kind == "separator" then
        local rhs, column = alternatives(tokens, 2)
        return rhs and "continuation" or nil, nil, rhs, column
    elseif first.kind == "directive" and first.value == "%start" then
        if not tokens[2] or tokens[2].kind ~= "nonterminal" then
            return nil, nil, nil, error_column(tokens, 2)
        end
        if tokens[3] then
            return nil, nil, nil, error_column(tokens, 3)
        end
        return "start", tokens[2].value
    elseif first.kind == "directive" and first.value == "%token" then
        if not tokens[2] then
            return nil, nil, nil, error_column(tokens, 2)
        end
        local words = {}
        for i = 2, #tokens do
            if tokens[i].kind ~= "word" then
                return nil, nil, nil, error_column(tokens, i)
            end
            words[#words + 1] = tokens[i].value
        end
        return "declaration", nil, words
    end
    return nil, nil, nil, first.start
end
function M.parse(lines)
    local grammar = {order = {}, rules = {}, diagnostics = {}, declared = {}, word_first = {}, has_declarations = false}
    local attached = nil
    for number, line in ipairs(lines) do
        local tokens = M.lex(line)
        local kind, lhs, values, column = line_form(tokens)
        if not kind then
            grammar.diagnostics[#grammar.diagnostics + 1] = "line " .. number .. ": syntax error at column " .. column
            attached = nil
        elseif kind == "start" then
            if grammar.start then
                grammar.diagnostics[#grammar.diagnostics + 1] = "line " .. number .. ": duplicate %start"
            else
                grammar.start = lhs
            end
            attached = nil
        elseif kind == "declaration" then
            grammar.has_declarations = true
            for _, value in ipairs(values) do
                grammar.declared[value] = true
            end
            attached = nil
        elseif kind ~= "blank" then
            if kind == "rule" then
                if not grammar.rules[lhs] then
                    grammar.order[#grammar.order + 1] = lhs
                    grammar.rules[lhs] = {}
                end
                attached = lhs
            elseif not attached then
                grammar.diagnostics[#grammar.diagnostics + 1] = "line " .. number .. ": continuation without a rule"
            end
            if attached then
                for _, token in ipairs(tokens) do
                    if token.kind == "word" and not grammar.word_first[token.value] then
                        grammar.word_first[token.value] = number
                    end
                end
                for _, rhs in ipairs(values) do
                    local duplicate = false
                    for _, prior in ipairs(grammar.rules[attached]) do
                        if M.same(rhs, prior) then
                            duplicate = true
                            break
                        end
                    end
                    if duplicate then
                        grammar.diagnostics[#grammar.diagnostics + 1] = "line " .. number .. ": duplicate alternative " .. M.production(attached, rhs)
                    else
                        grammar.rules[attached][#grammar.rules[attached] + 1] = rhs
                    end
                end
            end
        end
    end
    grammar.start = grammar.start or grammar.order[1]
    return grammar
end
return M
