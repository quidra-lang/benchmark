local M = {}
local keywords, pairs_set = {}, {}
for word in ("int bool void true false if else while for break continue return print read"):gmatch("%S+") do keywords[word] = true end
for word in ("<= >= == != && ||"):gmatch("%S+") do pairs_set[word] = true end
function M.fail(kind, position, message)
    error({ category = "compile", kind = kind, position = position, message = message }, 0)
end
function M.tokenize(lines)
    local parts = {}
    for _, record in ipairs(lines) do parts[#parts + 1] = record[2] end
    local source = table.concat(parts, "\n") .. "\n"
    local tokens, index, line, column = {}, 1, lines[1][1], 1
    while index <= #source do
        local ch, start, position = source:sub(index, index), index, { line, column }
        local pair = source:sub(index, index + 1)
        local kind, spelling
        if ch == " " or ch == "\n" then index = index + 1
        elseif pair == "//" then index = assert(source:find("\n", index, true))
        elseif pair == "/*" then
            local close = source:find("*/", index + 2, true)
            if not close then M.fail("lexical", position, "unterminated comment") end
            index = close + 2
        elseif ch:match("[A-Za-z_]") then
            spelling = source:sub(index):match("^[A-Za-z_][A-Za-z_0-9]*")
            kind, index = keywords[spelling] and "keyword" or "identifier", index + #spelling
        elseif ch:match("[0-9]") then
            spelling = source:sub(index):match("^[0-9]+")
            local digits = spelling:gsub("^0+", "")
            if #digits > 10 or (#digits == 10 and digits > "2147483647") then
                M.fail("lexical", position, "integer literal too large")
            end
            kind, index = "integer", index + #spelling
        elseif pairs_set[pair] then kind, spelling, index = "symbol", pair, index + 2
        elseif ("+-*/%<>=!(){}[],;"):find(ch, 1, true) then kind, spelling, index = "symbol", ch, index + 1
        else M.fail("lexical", position, "unexpected character '" .. ch .. "'") end
        if kind then tokens[#tokens + 1] = { kind = kind, spelling = spelling, position = position } end
        local consumed, last, count = source:sub(start, index - 1), false, 0
        for at in consumed:gmatch("()\n") do last, count = at, count + 1 end
        if count > 0 then line, column = line + count, #consumed - last + 1
        else column = column + #consumed end
    end
    local last = lines[#lines]
    tokens[#tokens + 1] = { kind = "end", spelling = "", position = { last[1], #last[2] + 1 } }
    return tokens
end
return M
