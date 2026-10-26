for _, original in ipairs({84, 9973, 15625, 1001, 123456, 48000, 999958, 999999}) do
    local remaining, divisor, factors = original, 2, {}
    while divisor * divisor <= remaining do
        local exponent = 0
        while remaining % divisor == 0 do
            remaining = remaining // divisor
            exponent = exponent + 1
        end
        if exponent > 0 then
            factors[#factors + 1] = exponent == 1 and tostring(divisor) or string.format("%d^%d", divisor, exponent)
        end
        divisor = divisor + 1
    end
    if remaining > 1 then factors[#factors + 1] = tostring(remaining) end
    io.write(string.format("%d = %s\n", original, table.concat(factors, " * ")))
end
