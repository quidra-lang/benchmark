local M = {}
function M.reflect(words,post)
    local result = {}
    for _,word in ipairs(words) do for _,replacement in ipairs(post[word] or {word}) do result[#result+1] = replacement end end
    return result
end
function M.reply(text,bindings,post)
    local result = text:gsub("%((%d)%)",function(number) return table.concat(M.reflect(bindings[tonumber(number)] or {},post)," ") end)
    result = result:gsub(" +"," "):match("^ *(.-) *$")
    return (result:gsub("^%l",string.upper))
end
function M.restate(arguments,bindings)
    local result = {}
    for i=2,#arguments do
        local number = arguments[i]:match("^%((%d)%)$")
        if number then for _,word in ipairs(bindings[tonumber(number)] or {}) do result[#result+1] = word end
        else result[#result+1] = arguments[i] end
    end
    return result
end
function M.wrap(text)
    local lines = {}; local line = "ELIZA:"
    for word in text:gmatch("[^ ]+") do
        if line == "ELIZA:" or #line+1+#word <= 72 then line = line.." "..word
        else lines[#lines+1] = line; line = "       "..word end
    end
    lines[#lines+1] = line
    return lines
end
return M
