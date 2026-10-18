for original in [7, 98000, 4096, 50301, 2718281, 123456789]
    decimal_digits = digits(original)
    reversed = parse(Int, reverse(string(original)))
    println(original, ": digits=", length(decimal_digits), " sum=", sum(decimal_digits), " reversed=", reversed)
end
