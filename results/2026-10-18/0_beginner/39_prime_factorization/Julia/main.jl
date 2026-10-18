for original in [84,9973,15625,1001,123456,48000,999958,999999]
    remaining, divisor = original, 2
    factors = String[]
    while divisor * divisor <= remaining
        factor_power = 0
        while remaining % divisor == 0
            remaining = div(remaining, divisor)
            factor_power += 1
        end
        if factor_power > 0
            push!(factors, factor_power == 1 ? string(divisor) : string(divisor, "^", factor_power))
        end
        divisor += 1
    end
    if remaining > 1
        push!(factors, string(remaining))
    end
    println(original, " = ", join(factors, " * "))
end
