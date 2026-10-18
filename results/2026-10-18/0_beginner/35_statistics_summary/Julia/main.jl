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
    mode_value, best = ordered[1], 0
    for value in unique(ordered)
        frequency = count(==(value), numbers)
        if frequency > best
            mode_value, best = value, frequency
        end
    end
    @printf("mean: %.3f\n", floor(average*1000+0.5)/1000)
    println("median: ", ordered[6])
    println("mode: ", mode_value)
    println("range: ", ordered[end]-ordered[1])
    @printf("stdev: %.3f\n", floor(deviation*1000+0.5)/1000)
end
main()
