local function euclid(a, b)
    while b ~= 0 do a, b = b, a % b end
    return a
end
for _, pair in ipairs({{48, 180}, {1071, 462}, {7, 91}, {13, 97}, {36288, 98280}}) do
    local a, b = pair[1], pair[2]
    local divisor = euclid(a, b)
    local multiple = (a // divisor) * b
    io.write(string.format("gcd(%d, %d) = %d, lcm(%d, %d) = %d\n", a, b, divisor, a, b, multiple))
end
