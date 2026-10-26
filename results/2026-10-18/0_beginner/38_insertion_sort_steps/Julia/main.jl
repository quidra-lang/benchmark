function main()
    numbers = [52, 17, 38, 9, 61, 38, 24, 45]
    total = 0
    for i = 2:8
        value, j, shifts = numbers[i], i-1, 0
        while j >= 1 && numbers[j] > value
            numbers[j+1] = numbers[j]
            shifts += 1
            j -= 1
        end
        numbers[j+1] = value
        total += shifts
        println("i=", i-1, " shifts=", shifts, ": ", join(numbers, " "))
    end
    println("total shifts: ", total)
end

main()
