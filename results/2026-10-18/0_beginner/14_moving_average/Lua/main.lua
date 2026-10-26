local sales = {120, 135, 98, 143, 160, 152, 171, 149, 188, 176}
for day = 3, #sales do
    local average = (sales[day - 2] + sales[day - 1] + sales[day]) / 3
    io.write(string.format("day %d: %.2f\n", day, average))
end
