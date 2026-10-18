for original in [7, 98000, 4096, 50301, 2718281, 123456789]
    remaining = original
    digit_count = 0
    digit_sum = 0
    reversed = 0
    while remaining > 0
        digit = remaining % 10
        digit_count += 1
        digit_sum += digit
        reversed = reversed * 10 + digit
        remaining = div(remaining, 10)
    end
    println(original, ": digits=", digit_count, " sum=", digit_sum, " reversed=", reversed)
end
