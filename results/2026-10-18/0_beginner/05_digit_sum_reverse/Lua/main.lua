for _, original in ipairs({7, 98000, 4096, 50301, 2718281, 123456789}) do
    local digits = tostring(original)
    local digit_sum = 0
    for digit in digits:gmatch("%d") do
        digit_sum = digit_sum + tonumber(digit)
    end
    io.write(string.format("%d: digits=%d sum=%d reversed=%d\n", original, #digits, digit_sum, tonumber(digits:reverse())))
end
