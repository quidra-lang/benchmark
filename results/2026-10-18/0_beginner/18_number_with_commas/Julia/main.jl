for n in [0, 7, 999, 1000, -456789, 3141592, 9876543210]
    decimal_text = string(abs(n))
    groups = String[]
    while length(decimal_text) > 3
        pushfirst!(groups, decimal_text[end-2:end])
        decimal_text = decimal_text[1:end-3]
    end
    pushfirst!(groups, decimal_text)
    println(n < 0 ? "-" : "", join(groups, ","))
end
