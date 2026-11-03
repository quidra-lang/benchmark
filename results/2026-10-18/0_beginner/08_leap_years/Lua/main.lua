for _, year in ipairs({1900, 1988, 2000, 2019, 2024, 2026, 2032, 2100}) do
    local leap = year % 400 == 0 or (year % 4 == 0 and year % 100 ~= 0)
    io.write(string.format("%04d: %s\n", year, leap and "leap year" or "common year"))
end
