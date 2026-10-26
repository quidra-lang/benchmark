for _, coefficients in ipairs({{1, -3, -10}, {-2, 5, 4}, {3, 1, -2}, {4, -12, 9}, {1, 2, 5}, {-2, 3, -4}}) do
    local a, b, c = table.unpack(coefficients)
    local discriminant = b * b - 4 * a * c
    io.write(string.format("%d %d %d: ", a, b, c))
    if discriminant > 0 then
        local first, second = (-b + math.sqrt(discriminant)) / (2 * a), (-b - math.sqrt(discriminant)) / (2 * a)
        io.write(string.format("x1 = %.4f, x2 = %.4f\n", math.max(first, second), math.min(first, second)))
    elseif discriminant == 0 then
        io.write(string.format("x = %.4f\n", -b / (2 * a)))
    else
        local real, imaginary = -b / (2 * a), math.sqrt(-discriminant) / (2 * math.abs(a))
        io.write(string.format("x = %.4f + %.4fi, %.4f - %.4fi\n", real, imaginary, real, imaginary))
    end
end
