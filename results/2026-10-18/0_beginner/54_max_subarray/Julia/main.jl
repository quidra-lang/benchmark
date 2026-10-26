arrays = [
    [3, -5, 8, -2, 6, -9, 4, 1, -7, 5, -3, 2],
    [-4, 7, -1, 3, -8, 10, -2, 5, -6, -2, 9, -12, 4, -1],
    [-6, -3, 5, -1, -4, 3, -9, 2, 3, -1, 4, -5, 1, 6, -2],
]
for numbers in arrays
    current = best = numbers[1]
    start = best_start = best_end = 1
    for i = 2:length(numbers)
        if numbers[i] > current+numbers[i]
            current = numbers[i]
            start = i
        else
            current += numbers[i]
        end
        if current > best
            best, best_start, best_end = current, start, i
        end
    end
    println("max sum ", best, " at [", best_start-1, ", ", best_end-1, "]")
end
