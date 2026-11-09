for original in [7, 98000, 4096, 50301, 2718281, 123456789]
    decimal_digits = digits(original)
    count = length(decimal_digits)
    reversed = parse(Int, reverse(string(original)))
    println(
        "$original: digits=$(count) sum=$(sum(decimal_digits)) reversed=$reversed",
    )
end
