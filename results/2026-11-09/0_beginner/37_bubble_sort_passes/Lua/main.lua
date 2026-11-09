local numbers, total = {27, 64, 13, 88, 41, 5, 72, 36}, 0
for pass = 1, 7 do
    local changed = false
    for j = 1, 8 - pass do
        if numbers[j] > numbers[j + 1] then
            numbers[j], numbers[j + 1] = numbers[j + 1], numbers[j]
            total = total + 1
            changed = true
        end
    end
    io.write(string.format("pass %d: %s\n", pass, table.concat(numbers, " ")))
    if not changed then break end
end
io.write(string.format("swaps: %d\n", total))
