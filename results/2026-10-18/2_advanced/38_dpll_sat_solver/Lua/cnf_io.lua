local M = {}
function M.valid_number(token)
    return #token <= 6 and (token == "0" or token:match("^[1-9][0-9]*$") ~= nil)
end
function M.valid_literal(token)
    if token == "0" then
        return true
    end
    local digits = token:sub(1, 1) == "-" and token:sub(2) or token
    return #digits <= 6 and digits:match("^[1-9][0-9]*$") ~= nil
end
function M.read(filename)
    local variables, declared, clauses, partial = nil, nil, {}, {}
    local number = 0
    for line in io.lines("input/" .. filename) do
        number = number + 1
        local tokens = {}
        for token in line:gmatch("[^ ]+") do
            tokens[#tokens + 1] = token
        end
        if line:sub(1, 1) ~= "c" and #tokens > 0 then
            if tokens[1] == "p" then
                if variables ~= nil then
                    return nil, nil, "duplicate header at line " .. number
                end
                if #tokens ~= 4 or tokens[2] ~= "cnf" or not M.valid_number(tokens[3]) or not M.valid_number(tokens[4]) then
                    return nil, nil, "bad header at line " .. number
                end
                variables, declared = tonumber(tokens[3]), tonumber(tokens[4])
            else
                if variables == nil then
                    return nil, nil, "missing header"
                end
                for _, token in ipairs(tokens) do
                    if not M.valid_literal(token) then
                        return nil, nil, "bad token " .. token .. " at line " .. number
                    end
                    local literal = tonumber(token)
                    if math.abs(literal) > variables then
                        return nil, nil, "literal out of range " .. token .. " at line " .. number
                    end
                    if literal == 0 then
                        clauses[#clauses + 1], partial = partial, {}
                    else
                        partial[#partial + 1] = literal
                    end
                end
            end
        end
    end
    if variables == nil then
        return nil, nil, "missing header"
    elseif #partial > 0 then
        return nil, nil, "unterminated clause"
    elseif #clauses ~= declared then
        return nil, nil, "clause count mismatch header=" .. declared .. " found=" .. #clauses
    end
    return variables, clauses, nil
end
function M.model_lines(model)
    local tokens, lines = {}, {}
    for variable, value in ipairs(model) do
        tokens[#tokens + 1] = tostring(value and variable or -variable)
    end
    tokens[#tokens + 1] = "0"
    for start = 1, #tokens, 10 do
        local parts = {}
        for i = start, math.min(start + 9, #tokens) do
            parts[#parts + 1] = tokens[i]
        end
        lines[#lines + 1] = "v " .. table.concat(parts, " ")
    end
    return lines
end
return M
