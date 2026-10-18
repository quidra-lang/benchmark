local numbers, total = {52,17,38,9,61,38,24,45}, 0
for i = 2, 8 do
    local value, j, shifts = numbers[i], i-1, 0
    while j >= 1 and numbers[j] > value do
        numbers[j+1] = numbers[j]
        shifts = shifts+1; j = j-1
    end
    numbers[j+1] = value
    total = total+shifts
    io.write(string.format("i=%d shifts=%d: %s\n",i-1,shifts,table.concat(numbers," ")))
end
io.write(string.format("total shifts: %d\n",total))
