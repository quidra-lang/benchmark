function main()
    numbers = [27,64,13,88,41,5,72,36]
    total = 0
    for pass in 1:7
        changed = false
        for j in 1:8-pass
            if numbers[j] > numbers[j+1]
                numbers[j], numbers[j+1] = numbers[j+1], numbers[j]
                total += 1
                changed = true
            end
        end
        println("pass ", pass, ": ", join(numbers, " "))
        !changed && break
    end
    println("swaps: ", total)
end
main()
