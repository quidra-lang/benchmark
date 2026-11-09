local L = {}
local keywords, builtins, pairs_set = {}, {}, {}
for word in ("BEGIN END function if else while for do break continue next exit return delete in getline print printf"):gmatch("%S+") do keywords[word] = true end
for word in ("length substr index split sprintf toupper tolower close int"):gmatch("%S+") do builtins[word] = true end
for word in ("+= -= *= /= %= ^= == <= >= != ++ -- && || >>"):gmatch("%S+") do pairs_set[word] = true end
local escapes = { n = "\n", t = "\t", ["\\"] = "\\", ['"'] = '"', ["/"] = "/" }
function L.fail(position) error({ category = "syntax", position = position }, 0) end
function L.tokenize(source)
    local tokens, index, line, column = {}, 1, 1, 1
    while index <= #source do
        local ch, start, position = source:sub(index, index), index, { line, column }
        local pair = source:sub(index, index + 1)
        if ch == " " then index, column = index + 1, column + 1
        elseif pair == "\\\n" then index, line, column = index + 2, line + 1, 1
        elseif ch == "#" then
            local ending = source:find("\n", index, true) or #source + 1
            column, index = column + ending - index, ending
        elseif ch == "\n" then
            tokens[#tokens + 1] = { kind = "newline", spelling = "\n", position = position }
            index, line, column = index + 1, line + 1, 1
        else
            local kind, value, ending = false, false, index + 1
            if ch:match("[0-9]") then
                local digits = source:sub(index):match("^[0-9]+")
                kind, value, ending = "number", tonumber(digits), index + #digits
            elseif ch:match("[A-Za-z_]") then
                local word = source:sub(index):match("^[A-Za-z_][A-Za-z_0-9]*")
                ending = index + #word
                if keywords[word] then kind = "keyword" elseif builtins[word] then kind = "builtin"
                else kind = source:sub(ending, ending) == "(" and "function_name" or "name" end
            elseif ch == '"' then
                local pieces = {}
                while ending <= #source and source:sub(ending, ending) ~= '"' do
                    local current = source:sub(ending, ending)
                    if current == "\n" then L.fail(position) end
                    if current == "\\" then
                        local escaped = escapes[source:sub(ending + 1, ending + 1)]
                        if not escaped then L.fail({ line, column + ending - start }) end
                        pieces[#pieces + 1], ending = escaped, ending + 2
                    else pieces[#pieces + 1], ending = current, ending + 1 end
                end
                if ending > #source then L.fail(position) end
                ending, kind, value = ending + 1, "string", table.concat(pieces)
            elseif pairs_set[pair] then kind, ending = "symbol", index + 2
            elseif ("+-*/%^!><?:=()[]{},;$"):find(ch, 1, true) then kind = "symbol"
            else L.fail(position) end
            tokens[#tokens + 1] = { kind = kind, spelling = source:sub(index, ending - 1), value = value, position = position }
            column, index = column + ending - index, ending
        end
    end
    local _, count = source:gsub("\n", "")
    tokens[#tokens + 1] = { kind = "end", spelling = "", position = { count + 1, 1 } }
    return tokens
end
return L
