for _, celsius in ipairs({-40, -15, -3, 0, 22, 37, 100}) do
    local fahrenheit = celsius * 9 / 5 + 32
    local rounded = math.floor(math.abs(fahrenheit) * 10 + 0.5) / 10
    if fahrenheit < 0 then rounded = -rounded end
    io.write(string.format("%d C = %.1f F\n", celsius, rounded))
end
