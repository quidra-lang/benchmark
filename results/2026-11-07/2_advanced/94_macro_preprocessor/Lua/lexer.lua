local L = {}
local punctuators = { "...", "<<=", ">>=", "->", "++", "--", "<<", ">>", "<=", ">=", "==", "!=", "&&", "||",
    "*=", "/=", "%=", "+=", "-=", "&=", "^=", "|=", "##", "[", "]", "(", ")", "{", "}", ".", "&", "*", "+", "-",
    "~", "!", "/", "%", "<", ">", "^", "|", "?", ":", ";", "=", ",", "#" }
function L.token(kind, spelling, line, space, hide)
    return { kind = kind, spelling = spelling, line = line, space = space, hide = hide or {} }
end
function L.clone(token, changes)
    local result = L.token(token.kind, token.spelling, token.line, token.space, token.hide)
    if changes then for key, value in pairs(changes) do result[key] = value end end
    return result
end
function L.read_token(text, position, header)
    position = position or 1
    local ch, ending = text:sub(position, position), position + 1
    if header and ch == "<" then
        local close, newline = text:find(">", ending, true), text:find("\n", ending, true)
        if close and (not newline or close < newline) then return "header", text:sub(position, close), close + 1 end
    end
    if ch:match("[A-Za-z_]") then
        local spelling = text:sub(position):match("^[A-Za-z_][A-Za-z_0-9]*")
        return "identifier", spelling, position + #spelling
    elseif ch:match("[0-9]") or (ch == "." and text:sub(ending, ending):match("[0-9]")) then
        while ending <= #text do
            local current, following = text:sub(ending, ending), text:sub(ending + 1, ending + 1)
            if current:match("[eEpP]") and (following == "+" or following == "-") then ending = ending + 2
            elseif current:match("[A-Za-z_0-9.]") then ending = ending + 1
            else break end
        end
        return "number", text:sub(position, ending - 1), ending
    elseif ch == '"' or ch == "'" then
        while ending <= #text and text:sub(ending, ending) ~= "\n" do
            local current = text:sub(ending, ending)
            if current == ch then return ch == '"' and "string" or "character", text:sub(position, ending), ending + 1 end
            if current == "\\" and ending < #text and text:sub(ending + 1, ending + 1) ~= "\n" then ending = ending + 2
            else ending = ending + 1 end
        end
    end
    for _, punctuator in ipairs(punctuators) do
        if text:sub(position, position + #punctuator - 1) == punctuator then return "punctuator", punctuator, position + #punctuator end
    end
    return "other", ch, position + 1
end
local function scan(text, positions, start)
    local lines, tokens, index, spaced = {}, {}, 1, true
    start = start or 1
    while index <= #text do
        local ch, pair = text:sub(index, index), text:sub(index, index + 1)
        if ch == " " then spaced, index = true, index + 1
        elseif ch == "\n" then
            local ending = positions[index]
            lines[#lines + 1] = { tokens = tokens, start = start, ending = ending }
            tokens, start, spaced, index = {}, ending + 1, true, index + 1
        elseif pair == "/*" then
            local close = text:find("*/", index + 2, true)
            index, spaced = close and close + 2 or #text + 1, true
        elseif pair == "//" then index, spaced = text:find("\n", index + 2, true) or #text + 1, true
        else
            local header = #tokens == 2 and tokens[1].spelling == "#" and tokens[2].spelling == "include"
            local kind, spelling, ending = L.read_token(text, index, header)
            tokens[#tokens + 1] = L.token(kind, spelling, positions[index], spaced)
            index, spaced = ending, false
        end
    end
    if #tokens > 0 then lines[#lines + 1] = { tokens = tokens, start = start, ending = positions[#positions] } end
    return lines
end
function L.source(text)
    local characters, positions, index, line = {}, {}, 1, 1
    while index <= #text do
        if text:sub(index, index + 1) == "\\\n" then index, line = index + 2, line + 1
        else
            local ch = text:sub(index, index)
            characters[#characters + 1], positions[#positions + 1] = ch, line
            if ch == "\n" then line = line + 1 end
            index = index + 1
        end
    end
    return scan(table.concat(characters), positions, 1)
end
function L.definition(text, line)
    text = text .. "\n"
    local positions, result = {}, {}
    for i = 1, #text do positions[i] = line end
    for _, logical in ipairs(scan(text, positions, line)) do
        for _, token in ipairs(logical.tokens) do result[#result + 1] = token end
    end
    return result
end
function L.render(tokens)
    local pieces = {}
    for i, token in ipairs(tokens) do
        if i > 1 and token.space then pieces[#pieces + 1] = " " end
        pieces[#pieces + 1] = token.spelling
    end
    return table.concat(pieces)
end
function L.single_token(text)
    if text == "" or text:sub(1, 2) == "//" or text:sub(1, 2) == "/*" then return false end
    local kind, _, ending = L.read_token(text)
    return ending == #text + 1 and kind or false
end
return L
