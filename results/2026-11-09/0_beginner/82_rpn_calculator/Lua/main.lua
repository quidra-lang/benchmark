local function evaluate(expression)
    local stack = {}
    for token in expression:gmatch("%S+") do
        if token == "+" or token == "-" or token == "*" or token == "/" then
            if #stack < 2 then return "error: stack underflow" end
            local b = table.remove(stack)
            local a = table.remove(stack)
            if token == "/" and b == 0 then return "error: division by zero" end
            local value
            if token == "+" then
                value = a + b
            elseif token == "-" then
                value = a - b
            elseif token == "*" then
                value = a * b
            else
                value = math.abs(a) // math.abs(b)
                if (a < 0) ~= (b < 0) then value = -value end
            end
            stack[#stack + 1] = value
        else
            stack[#stack + 1] = tonumber(token)
        end
    end
    return #stack == 1 and tostring(stack[1]) or "error: leftover operands"
end

local expressions = {
    "3 4 + 2 *", "-17 5 / 4 -3 * -", "1 2 + * 3", "15 7 1 1 + - / 3 * 2 1 1 + + -",
    "4 2 5 * + 1 3 2 * - 5 + /", "2 3 4 + 5", "46341 46339 * -2 /",
}
for _, expression in ipairs(expressions) do io.write(expression, " => ", evaluate(expression), "\n") end
