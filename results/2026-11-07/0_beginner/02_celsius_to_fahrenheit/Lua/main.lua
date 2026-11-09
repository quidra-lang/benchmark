for _, celsius in ipairs({-40, -15, -3, 0, 22, 37, 100}) do
    local fahrenheit = celsius * 9 / 5 + 32
    io.write(string.format("%d C = %.1f F\n", celsius, fahrenheit))
end
