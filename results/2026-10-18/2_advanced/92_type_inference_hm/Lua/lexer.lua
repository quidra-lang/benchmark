local M = {}
local keywords, symbols = {}, {}
for word in ("let rec and in fun if then else match with true false mod val"):gmatch("%S+") do keywords[word] = true end
for word in (";; -> :: : || && <= >= <> ; = < > + - * / ^ ( ) [ ] , |"):gmatch("%S+") do symbols[word] = true end
local escapes = { n = "\n", t = "\t", ["\\"] = "\\", ['"'] = '"' }
function M.is_name(token) return token.kind == "identifier" and token.spelling ~= "_" end
function M.tokenize(source, filename)
    local tokens, index, line, column = {}, 1, 1, 1
    while index <= #source do
        local start, position = index, { filename, line, column }
        local ch, kind, value = source:sub(index, index)
        if ch == " " or ch == "\n" then index = index + 1
        elseif source:sub(index, index + 1) == "(*" then
            local close = source:find("*)", index + 2, true)
            if close then index = close + 2
            else kind, value, index = "invalid", "unterminated comment", #source + 1 end
        elseif ch:match("[0-9]") then
            local run = source:sub(index):match("^[0-9]+")
            index = index + #run
            local digits = run:gsub("^0+", "")
            if digits == "" then digits = "0" end
            if #digits > 10 or (#digits == 10 and digits > "2147483647") then
                kind, value = "invalid", "integer literal too large"
            else kind, value = "integer", tonumber(digits) end
        elseif ch:match("[A-Za-z_]") then
            value = source:sub(index):match("^[A-Za-z_][A-Za-z_0-9']*")
            index, kind = index + #value, keywords[value] and value or "identifier"
        elseif ch == "'" and source:sub(index + 1, index + 1):match("[a-z]") then
            value = source:sub(index):match("^'[a-z][A-Za-z_0-9]*")
            index, kind = index + #value, "type_variable"
        elseif ch == '"' then
            index = index + 1
            local decoded, invalid = {}, false
            while index <= #source and source:sub(index, index) ~= '"' and source:sub(index, index) ~= "\n" do
                local current, next_ch = source:sub(index, index), source:sub(index + 1, index + 1)
                if current == "\\" and next_ch ~= "" and next_ch ~= "\n" then
                    if escapes[next_ch] then decoded[#decoded + 1] = escapes[next_ch] else invalid = true end
                    index = index + 2
                else decoded[#decoded + 1], index = current, index + 1 end
            end
            if index > #source or source:sub(index, index) == "\n" then kind, value = "invalid", "unterminated string"
            else
                index = index + 1
                kind, value = invalid and "invalid" or "string", invalid and "invalid escape sequence" or table.concat(decoded)
            end
        else
            local pair = source:sub(index, index + 1)
            if symbols[pair] then kind, value, index = pair, pair, index + 2
            elseif symbols[ch] then kind, value, index = ch, ch, index + 1
            else kind, value, index = "invalid", "illegal character '" .. ch .. "'", index + 1 end
        end
        local consumed = source:sub(start, index - 1)
        if kind then tokens[#tokens + 1] = { kind = kind, spelling = consumed, value = value, position = position } end
        local newlines, last = 0, false
        for p in consumed:gmatch("()\n") do newlines, last = newlines + 1, p end
        if newlines > 0 then line, column = line + newlines, #consumed - last + 1
        else column = column + #consumed end
    end
    local _, count = source:gsub("\n", "")
    tokens[#tokens + 1] = { kind = "EOF", spelling = "", position = { filename, count + 1, 1 } }
    return tokens
end
return M
