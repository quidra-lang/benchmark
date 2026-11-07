function euclid(a, b)
    while b != 0
        a, b = b, a % b
    end
    return a
end

for (a, b) in [(48, 180), (1071, 462), (7, 91), (13, 97), (36288, 98280)]
    divisor = euclid(a, b)
    multiple = div(a, divisor) * b
    println("gcd(", a, ", ", b, ") = ", divisor, ", lcm(", a, ", ", b, ") = ", multiple)
end
