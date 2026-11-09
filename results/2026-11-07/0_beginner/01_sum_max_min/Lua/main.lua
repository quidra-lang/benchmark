local values = {17, -8, 42, 5, -23, 36, 5, 0, -11, 29}
local total, maximum, minimum = 0, values[1], values[1]
for _, value in ipairs(values) do
    total = total + value
    maximum = math.max(maximum, value)
    minimum = math.min(minimum, value)
end
io.write(string.format("sum: %d\nmax: %d\nmin: %d\n", total, maximum, minimum))
