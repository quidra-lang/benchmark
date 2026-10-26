local arrays = {
    {3, -5, 8, -2, 6, -9, 4, 1, -7, 5, -3, 2},
    {-4, 7, -1, 3, -8, 10, -2, 5, -6, -2, 9, -12, 4, -1},
    {-6, -3, 5, -1, -4, 3, -9, 2, 3, -1, 4, -5, 1, 6, -2},
}
for _, numbers in ipairs(arrays) do
    local current, best, start, best_start, best_end = numbers[1], numbers[1], 1, 1, 1
    for i = 2, #numbers do
        if numbers[i] > current + numbers[i] then
            current = numbers[i]
            start = i
        else
            current = current + numbers[i]
        end
        if current > best then best, best_start, best_end = current, start, i end
    end
    io.write(string.format("max sum %d at [%d, %d]\n", best, best_start - 1, best_end - 1))
end
