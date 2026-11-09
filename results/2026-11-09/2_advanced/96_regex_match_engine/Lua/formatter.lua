local F = {}
function F.display(code)
    if code >= 33 and code <= 126 and code ~= 92 and code ~= 93 and code ~= 94 and code ~= 45 then return string.char(code) end
    return string.format("\\x%02X", code)
end
function F.set_notation(set, negated)
    local parts, code = {}, 0
    while code <= 127 do
        if not set[code] then code = code + 1
        else
            local last = code
            while last < 127 and set[last + 1] do last = last + 1 end
            local first_text, last_text = F.display(code), F.display(last)
            parts[#parts + 1] = last == code and first_text or (last == code + 1 and first_text .. last_text or first_text .. "-" .. last_text)
            code = last + 1
        end
    end
    return "[" .. (negated and "^" or "") .. table.concat(parts) .. "]"
end
function F.instruction(ins)
    local op = ins.op
    if op == "CHAR" then return "CHAR " .. F.display(ins.char)
    elseif op == "CLASS" then return "CLASS " .. F.set_notation(ins.set, ins.neg)
    elseif op == "SPLIT" then return "SPLIT " .. ins.x .. ", " .. ins.y
    elseif op == "JMP" then return "JMP " .. ins.x
    elseif op == "SAVE" then return "SAVE " .. ins.slot
    elseif op == "ASSERT" then return "ASSERT " .. ins.kind
    elseif op == "BACKREF" then return "BACKREF " .. ins.group
    elseif op == "LOOK" then return "LOOK " .. ins.kind .. " " .. ins.x end
    return op
end
function F.quoted(text)
    local parts = { '"' }
    local escapes = { [92] = "\\\\", [34] = '\\"', [10] = "\\n", [9] = "\\t" }
    for i = 1, #text do parts[#parts + 1] = escapes[text:byte(i)] or text:sub(i, i) end
    parts[#parts + 1] = '"'
    return table.concat(parts)
end
return F
