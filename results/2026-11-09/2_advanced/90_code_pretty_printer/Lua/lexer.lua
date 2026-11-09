local M = {}
local keywords, types, doubles = {}, {}, {}
for word in ("int float bool string void if else while for return break continue true false switch case default"):gmatch("%S+") do
    keywords[word] = true
end
for word in ("int float bool string void"):gmatch("%S+") do types[word] = true end
for word in ("<= >= == != && || += -= *= /= %="):gmatch("%S+") do doubles[word] = true end
M.types = types
M.assignment = { ["="] = true, ["+="] = true, ["-="] = true,
    ["*="] = true, ["/="] = true, ["%="] = true }

function M.fail(line, column, message)
    error({ line = line, column = column, message = message }, 0)
end

function M.lex(lines)
    local tokens, comments, items = {}, {}, {}
    local previous = 0
    for row, line in ipairs(lines) do
        local pos = 1
        while pos <= #line do
            local ch = line:sub(pos, pos)
            if ch == " " then
                pos = pos + 1
            else
                local start, kind, value = pos
                local pair = line:sub(pos, pos + 1)
                if pair == "//" then
                    kind, value, pos = "line_comment", line:sub(pos):gsub(" +$", ""), #line + 1
                elseif pair == "/*" then
                    local close = line:find("*/", pos + 2, true)
                    if not close then M.fail(row, pos, "unterminated comment") end
                    kind, value, pos = "block_comment", line:sub(pos, close + 1), close + 2
                elseif ch:match("[A-Za-z_]") then
                    value = line:sub(pos):match("^[A-Za-z_][A-Za-z_0-9]*")
                    kind, pos = keywords[value] and "keyword" or "identifier", pos + #value
                elseif ch:match("[0-9]") then
                    value = line:sub(pos):match("^[0-9]+%.[0-9]+") or line:sub(pos):match("^[0-9]+")
                    kind, pos = "number", pos + #value
                elseif ch == '"' then
                    pos = pos + 1
                    local closed = false
                    while pos <= #line do
                        local c = line:sub(pos, pos)
                        if c == "\\" then pos = pos + 2
                        elseif c == '"' then pos, closed = pos + 1, true; break
                        else pos = pos + 1 end
                    end
                    if not closed then M.fail(row, start, "unterminated string") end
                    kind, value = "string", line:sub(start, pos - 1)
                elseif doubles[pair] then
                    kind, value, pos = "symbol", pair, pos + 2
                elseif ("+-*/%<>=!()[]{},;.?:"):find(ch, 1, true) then
                    kind, value, pos = "symbol", ch, pos + 1
                else
                    M.fail(row, pos, "unexpected character '" .. ch .. "'")
                end
                local entry = { kind = kind, text = value, line = row, column = start,
                    blank = math.max(0, row - previous - 1), leading = {}, trailing = {},
                    allowed = false, trailing_comma = false }
                previous = row
                items[#items + 1] = entry
                if kind == "line_comment" or kind == "block_comment" then
                    comments[#comments + 1] = entry
                else
                    tokens[#tokens + 1] = entry
                    entry.index = #tokens
                end
            end
        end
    end
    tokens[#tokens + 1] = { kind = "end", text = "", line = #lines + 1, column = 1,
        blank = 0, index = #tokens + 1, leading = {}, trailing = {}, allowed = true }
    return tokens, comments, items
end

return M
