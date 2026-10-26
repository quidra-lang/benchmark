local function tokenize(line)
    local tokens, i = {}, 1
    while i <= #line do
        local c = line:sub(i, i)
        if c == " " then
            i = i + 1
        elseif c:match("[0-9a-z]") then
            local pattern = c:match("%d") and "%d" or "[a-z]"
            local first = i
            repeat i = i + 1 until i > #line or not line:sub(i, i):match(pattern)
            tokens[#tokens + 1] = line:sub(first, i - 1)
        else
            tokens[#tokens + 1] = c
            i = i + 1
        end
    end
    return tokens
end

local function evaluate(tokens, variables, position)
    local expression, term, factor
    factor = function()
        local token = tokens[position]
        position = position + 1
        if token == "-" then return -factor() end
        if token == "(" then
            local value = expression()
            position = position + 1
            return value
        end
        local number = tonumber(token)
        if number then return number end
        if variables[token] == nil then error("undefined variable " .. token, 0) end
        return variables[token]
    end
    term = function()
        local value = factor()
        while tokens[position] == "*" or tokens[position] == "/" do
            local operation = tokens[position]
            position = position + 1
            local right = factor()
            if operation == "/" and right == 0 then error("division by zero", 0) end
            if operation == "*" then
                value = value * right
            else
                local quotient = math.abs(value) // math.abs(right)
                value = (value < 0) ~= (right < 0) and -quotient or quotient
            end
        end
        return value
    end
    expression = function()
        local value = term()
        while tokens[position] == "+" or tokens[position] == "-" do
            local operation = tokens[position]
            position = position + 1
            local right = term()
            value = operation == "+" and value + right or value - right
        end
        return value
    end
    return expression()
end

local lines = {
    "width = 12", "height = width - 5", "area = width * height", "(area + 6) / 4",
    "shift = -area / 8 + 3", "height = 100 / (height - 7) + bonus", "volume = area * depth",
    "width = (width+3)*-(2-4)", "width * shift - height",
}
local variables = {}
for _, line in ipairs(lines) do
    local tokens = tokenize(line)
    local assignment = tokens[2] == "="
    local success, value = pcall(evaluate, tokens, variables, assignment and 3 or 1)
    if not success then
        io.write("error: ", value, "\n")
    elseif assignment then
        variables[tokens[1]] = value
        io.write(string.format("%s = %d\n", tokens[1], value))
    else
        io.write(string.format("%d\n", value))
    end
end
