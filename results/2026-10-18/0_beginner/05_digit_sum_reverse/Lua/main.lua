for _, original in ipairs({7, 98000, 4096, 50301, 2718281, 123456789}) do
    local remaining = original
    local count, digit_sum, reversed = 0, 0, 0
    while remaining > 0 do
        local digit = remaining % 10
        count = count + 1
        digit_sum = digit_sum + digit
        reversed = reversed * 10 + digit
        remaining = remaining // 10
    end
    io.write(string.format("%d: digits=%d sum=%d reversed=%d\n", original, count, digit_sum, reversed))
end
