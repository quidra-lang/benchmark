using Printf
function main()
    numbers = [72,85,64,90,85,58,77,85,69,93,71]
    average = sum(numbers) / length(numbers)
    squares = 0.0
    for value in numbers
        difference = value - average
        squares += difference * difference
    end
    deviation = sqrt(squares / length(numbers))
    ordered = sort(numbers)
    mode_value = argmax(value -> count(==(value), numbers), unique(ordered))
    @printf("mean: %.3f\n", average)
    println("median: ", ordered[6])
    println("mode: ", mode_value)
    println("range: ", ordered[end]-ordered[1])
    @printf("stdev: %.3f\n", deviation)
end
main()
